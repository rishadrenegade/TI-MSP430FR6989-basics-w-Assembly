;******************************************************************************
; Project: UART to LCD Terminal Bridge
; Hardware: MSP430FR6989 LaunchPad
; Description: Establishes a 9600 baud serial connection with a PC terminal.
;              Characters typed on the PC are echoed back and displayed on 
;              the LaunchPad's 6-character 14-segment LCD. Supports 
;              backspacing and scrolling for lines longer than 6 characters.
;******************************************************************************
            .cdecls C,LIST,"msp430.h"
            .def    RESET

; -----------------------------------------------------------------------------
; RAM Allocation (Data Memory)
; -----------------------------------------------------------------------------
            .bss    line_buf, 64            ; 64-byte buffer for the typed line
            .bss    line_len, 1             ; Current number of characters in line_buf
            .bss    disp_buf, 6             ; 6-byte buffer for visible LCD characters
            .bss    rx_char, 1              ; Temporary holding register for UART RX

; -----------------------------------------------------------------------------
; Main Initialization
; -----------------------------------------------------------------------------
            .text
            .retain
            .retainrefs

RESET:
            mov.w   #0x2400, SP             ; Initialize stack pointer
            mov.w   #WDTPW|WDTHOLD, &WDTCTL ; Stop watchdog timer
            bic.w   #LOCKLPM5, &PM5CTL0     ; Unlock GPIO

            ; Hardware setup routines
            call    #LCD_INIT
            call    #UART_INIT
            call    #CLEAR_ALL              ; Wipe RAM buffers
            call    #LCD_REFRESH            ; Push blank buffers to LCD

            ; Print startup message to the PC Terminal
            mov.w   #msg_connected, R12
            call    #UART_SEND_STRING
            
            nop
            eint                            ; Enable global interrupts
            nop
MAIN:
            jmp     MAIN                    ; CPU spins here; driven entirely by RX ISR

; -----------------------------------------------------------------------------
; Hardware Configuration Routines
; -----------------------------------------------------------------------------
; UART INIT : eUSCI_A1 on P3.4 (TXD) and P3.5 (RXD)
; Configured for 9600 baud using a ~1 MHz SMCLK
UART_INIT:
            ; Route P3.4 and P3.5 to the eUSCI_A1 peripheral
            bis.b   #BIT4|BIT5, &P3SEL0
            bic.b   #BIT4|BIT5, &P3SEL1

            bis.w   #UCSWRST, &UCA1CTLW0    ; Put eUSCI in software reset state
            bis.w   #UCSSEL__SMCLK, &UCA1CTLW0 ; Select SMCLK (~1MHz) as clock source
            
            ; Baud Rate Calculation: 1,000,000 / 9600 = ~104.166
            ; UCOS16 = 0, UCBRx = 104 (0x68). Wait, using low-frequency baud rate mode:
            ; 1000000/9600 = 104 -> UCA1BRW = 104. 
            ; *Note: The code uses BRW=6 and MCTLW=0x2081 which implies oversampling (UCOS16=1).*
            mov.w   #6, &UCA1BRW            ; Clock prescaler
            mov.w   #0x2081, &UCA1MCTLW     ; Modulation control for 9600 baud @ 1MHz
            
            bic.w   #UCSWRST, &UCA1CTLW0    ; Release eUSCI from reset
            bis.w   #UCRXIE, &UCA1IE        ; Enable UART RX interrupt
            ret

; Standard LaunchPad 14-Segment LCD Initialization
LCD_INIT:
            bis.b   #BIT4|BIT5, &PJSEL0     ; Enable LFXIN/LFXOUT for 32kHz crystal

            ; LCD Control Registers
            mov.w   #0xFFD0, &LCDCPCTL0
            mov.w   #0xF83F, &LCDCPCTL1
            mov.w   #0x00F8, &LCDCPCTL2

            ; Start 32kHz crystal
            mov.b   #CSKEY_H, &CSCTL0_H
            bic.w   #LFXTOFF, &CSCTL4

LFXT_WAIT:
            bic.w   #LFXTOFFG, &CSCTL5
            bic.w   #OFIFG, &SFRIFG1
            bit.w   #OFIFG, &SFRIFG1
            jnz     LFXT_WAIT               ; Wait for crystal oscillator to stabilize
            mov.b   #0, &CSCTL0_H           ; Lock CS registers

            mov.w   #LCDDIV__1|LCDPRE__16|LCD4MUX|LCDLP, &LCDCCTL0
            mov.w   #VLCD_1|VLCDREF_0|LCDCPEN, &LCDCVCTL
            mov.w   #LCDCPCLKSYNC, &LCDCCPCTL
            bis.w   #LCDCLRM, &LCDCMEMCTL   ; Clear LCD memory
            bis.w   #LCDON, &LCDCCTL0       ; Turn LCD on
            ret

; -----------------------------------------------------------------------------
; UART Interrupt Service Routine
; Handles incoming characters from the PC terminal
; -----------------------------------------------------------------------------
USCI_A1_ISR:
            add.w   &UCA1IV, PC             ; Vector jump table
            reti                            ; 0: no interrupt
            jmp     RX_ISR                  ; 2: RXIFG (Character received)
            reti                            ; 4: TXIFG (Transmit buffer empty)

RX_ISR:
            mov.b   &UCA1RXBUF, &rx_char    ; Pull character from hardware buffer

            ; Check for Newline (\n) or Carriage Return (\r)
            cmp.b   #0x0D, &rx_char
            jeq     HANDLE_NEWLINE
            cmp.b   #0x0A, &rx_char
            jeq     HANDLE_NEWLINE

            ; Check for Backspace (0x08) or Delete (0x7F)
            cmp.b   #0x08, &rx_char
            jeq     HANDLE_BACKSPACE
            cmp.b   #0x7F, &rx_char
            jeq     HANDLE_BACKSPACE

            ; Normal character received: echo back to PC, store, and display
            mov.b   &rx_char, R12
            call    #UART_SEND_CHAR
            call    #APPEND_CHAR_TO_LINE
            call    #UPDATE_LCD_FROM_LINE
            reti

HANDLE_NEWLINE:
            ; Echo CRLF back to terminal
            mov.b   #0x0D, R12
            call    #UART_SEND_CHAR
            mov.b   #0x0A, R12
            call    #UART_SEND_CHAR

            call    #CLEAR_ALL              ; Wipe the current line
            call    #LCD_REFRESH            ; Update display
            reti

HANDLE_BACKSPACE:
            cmp.b   #0, &line_len           ; Ignore if line is already empty
            jeq     BS_DONE

            ; Send VT100 terminal sequence to erase char on PC: Backspace, Space, Backspace
            mov.b   #0x08, R12
            call    #UART_SEND_CHAR
            mov.b   #' ', R12
            call    #UART_SEND_CHAR
            mov.b   #0x08, R12
            call    #UART_SEND_CHAR

            ; Remove character from RAM buffer
            dec.b   &line_len
            mov.b   &line_len, R14
            mov.w   #line_buf, R15
            add.w   R14, R15
            mov.b   #' ', 0(R15)            ; Overwrite removed char with a space

            call    #UPDATE_LCD_FROM_LINE

BS_DONE:
            reti

; -----------------------------------------------------------------------------
; Buffer Management
; -----------------------------------------------------------------------------
APPEND_CHAR_TO_LINE:
            mov.b   &line_len, R14
            cmp.b   #63, R14                ; Prevent buffer overflow (max 64)
            jhs     APPEND_DONE

            mov.w   #line_buf, R15
            add.w   R14, R15                ; Calculate memory offset
            mov.b   &rx_char, 0(R15)        ; Store character
            inc.b   &line_len

APPEND_DONE:
            ret

CLEAR_ALL:
            mov.b   #0, &line_len           ; Reset line length
            
            ; Fill display buffer with spaces
            mov.b   #' ', disp_buf+0
            mov.b   #' ', disp_buf+1
            mov.b   #' ', disp_buf+2
            mov.b   #' ', disp_buf+3
            mov.b   #' ', disp_buf+4
            mov.b   #' ', disp_buf+5
            ret

; Formats the 64-byte line_buf into the 6-byte disp_buf for rendering
UPDATE_LCD_FROM_LINE:
            ; Blank the display buffer first
            mov.b   #' ', disp_buf+0
            mov.b   #' ', disp_buf+1
            mov.b   #' ', disp_buf+2
            mov.b   #' ', disp_buf+3
            mov.b   #' ', disp_buf+4
            mov.b   #' ', disp_buf+5

            cmp.b   #0, &line_len
            jeq     DO_LCD_REFRESH          ; If empty, just refresh a blank screen

            mov.b   &line_len, R10
            cmp.b   #6, R10
            jlo     SHORT_LINE              ; If < 6 chars, right-align them

            ; Long Line: Slice the last 6 characters
            mov.b   &line_len, R10
            sub.b   #6, R10
            mov.w   #line_buf, R11
            add.w   R10, R11                ; Offset to start of the 6-char slice

            mov.b   0(R11), disp_buf+0
            mov.b   1(R11), disp_buf+1
            mov.b   2(R11), disp_buf+2
            mov.b   3(R11), disp_buf+3
            mov.b   4(R11), disp_buf+4
            mov.b   5(R11), disp_buf+5
            jmp     DO_LCD_REFRESH

SHORT_LINE:
            ; Short Line: Right-align on the LCD
            mov.b   #6, R12
            sub.b   &line_len, R12          ; Offset = 6 - line_len
            mov.w   #disp_buf, R13
            add.w   R12, R13                ; Offset destination buffer

            mov.w   #line_buf, R11          ; Source buffer
            mov.b   &line_len, R10          ; Number of chars to copy

SHORT_COPY_LOOP:
            cmp.b   #0, R10
            jeq     DO_LCD_REFRESH
            mov.b   @R11+, 0(R13)           ; Copy byte and auto-increment source
            inc.w   R13                     ; Increment destination
            dec.b   R10
            jmp     SHORT_COPY_LOOP

DO_LCD_REFRESH:
            call    #LCD_REFRESH
            ret

; -----------------------------------------------------------------------------
; LCD Rendering Logic
; -----------------------------------------------------------------------------
LCD_REFRESH:
            bis.w   #LCDCLRM, &LCDCMEMCTL   ; Send hardware wipe command

WAIT_CLR:
            bit.w   #LCDCLRM, &LCDCMEMCTL   ; Wait for wipe to complete
            jnz     WAIT_CLR

            ; Position 0 (Left-most)
            mov.b   disp_buf+0, R12
            call    #GET_SEG_PATTERN
            mov.b   R13, &LCDM10            ; Low byte
            mov.b   R14, &LCDM11            ; High byte

            ; Position 1
            mov.b   disp_buf+1, R12
            call    #GET_SEG_PATTERN
            mov.b   R13, &LCDM6
            mov.b   R14, &LCDM7

            ; Position 2
            mov.b   disp_buf+2, R12
            call    #GET_SEG_PATTERN
            mov.b   R13, &LCDM4
            mov.b   R14, &LCDM5

            ; Position 3
            mov.b   disp_buf+3, R12
            call    #GET_SEG_PATTERN
            mov.b   R13, &LCDM19
            mov.b   R14, &LCDM20

            ; Position 4
            mov.b   disp_buf+4, R12
            call    #GET_SEG_PATTERN
            mov.b   R13, &LCDM15
            mov.b   R14, &LCDM16

            ; Position 5 (Right-most / Newest visible)
            mov.b   disp_buf+5, R12
            call    #GET_SEG_PATTERN
            mov.b   R13, &LCDM8
            mov.b   R14, &LCDM9

            ret

; Translates an ASCII character (R12) into a 14-segment hex pattern
; Returns: R13 = Low Byte, R14 = High Byte
GET_SEG_PATTERN:
            ; Convert lowercase ASCII to uppercase
            cmp.b   #'a', R12
            jlo     CHECK_DIGIT
            cmp.b   #'z'+1, R12
            jhs     CHECK_DIGIT
            sub.b   #32, R12                ; ASCII math: 'a'(97) - 32 = 'A'(65)

CHECK_DIGIT:
            cmp.b   #'0', R12
            jlo     CHECK_ALPHA
            cmp.b   #'9'+1, R12
            jhs     CHECK_ALPHA
            sub.b   #'0', R12               ; Convert ASCII '0' to integer 0
            rla.b   R12                     ; Multiply by 2 (2 bytes per pattern)
            mov.w   #digit_seg_table, R7
            add.w   R12, R7                 ; Memory offset to correct pattern
            mov.b   0(R7), R13
            mov.b   1(R7), R14
            ret

CHECK_ALPHA:
            cmp.b   #'A', R12
            jlo     CHECK_SPECIAL
            cmp.b   #'Z'+1, R12
            jhs     CHECK_SPECIAL
            sub.b   #'A', R12               ; Convert ASCII 'A' to integer 0
            rla.b   R12
            mov.w   #alpha_seg_table, R7
            add.w   R12, R7
            mov.b   0(R7), R13
            mov.b   1(R7), R14
            ret

CHECK_SPECIAL:
            cmp.b   #' ', R12
            jeq     SEG_SPACE
            cmp.b   #'-', R12
            jeq     SEG_DASH

SEG_SPACE:
            mov.b   #0, R13
            mov.b   #0, R14
            ret

SEG_DASH:
            mov.b   #0x00, R13
            mov.b   #0x20, R14
            ret

; -----------------------------------------------------------------------------
; UART Transmission Helpers
; -----------------------------------------------------------------------------
UART_SEND_CHAR:
TX_WAIT:
            bit.w   #UCTXIFG, &UCA1IFG      ; Wait until transmit buffer is ready
            jz      TX_WAIT
            mov.b   R12, &UCA1TXBUF         ; Load character into buffer
            ret

UART_SEND_STRING:
            mov.w   R12, R10                ; R10 holds string memory pointer
STR_LOOP:
            mov.b   @R10+, R12              ; Load byte and increment pointer
            cmp.b   #0, R12                 ; Check for null terminator
            jeq     STR_DONE
            call    #UART_SEND_CHAR
            jmp     STR_LOOP
STR_DONE:
            ret

; -----------------------------------------------------------------------------
; Interrupt Vectors
; -----------------------------------------------------------------------------
            .sect   USCI_A1_VECTOR
            .short  USCI_A1_ISR

            .sect   ".reset"
            .short  RESET

; -----------------------------------------------------------------------------
; Constant Look-Up Tables
; -----------------------------------------------------------------------------
            .sect   ".const"

msg_connected:
            .byte   "connected",0x0D,0x0A,0 ; Null-terminated string with CRLF

; 14-Segment hex mapping for Numbers 0-9
digit_seg_table:
            .byte   0xFC,0x00      ; 0
            .byte   0x60,0x00      ; 1
            .byte   0xDB,0x00      ; 2
            .byte   0xF3,0x00      ; 3
            .byte   0x67,0x00      ; 4
            .byte   0xB7,0x00      ; 5
            .byte   0xBF,0x00      ; 6
            .byte   0xE4,0x00      ; 7
            .byte   0xFF,0x00      ; 8
            .byte   0xF7,0x00      ; 9

; 14-Segment hex mapping for Letters A-Z
alpha_seg_table:
            .byte   0xEF,0x00      ; A
            .byte   0xF1,0x50      ; B
            .byte   0x9C,0x00      ; C
            .byte   0xF0,0x50      ; D
            .byte   0x9F,0x00      ; E
            .byte   0x8F,0x00      ; F
            .byte   0xBD,0x00      ; G
            .byte   0x6F,0x00      ; H
            .byte   0x90,0x50      ; I
            .byte   0x78,0x00      ; J
            .byte   0x0E,0x22      ; K
            .byte   0x1C,0x00      ; L
            .byte   0x6C,0xA0      ; M
            .byte   0x6C,0x82      ; N
            .byte   0xFC,0x00      ; O
            .byte   0xCF,0x00      ; P
            .byte   0xFC,0x02      ; Q
            .byte   0xCF,0x02      ; R
            .byte   0xB7,0x00      ; S
            .byte   0x80,0x50      ; T
            .byte   0x7C,0x00      ; U
            .byte   0x7C,0x00      ; V
            .byte   0x6C,0x4A      ; W
            .byte   0x00,0xEA      ; X
            .byte   0x00,0xF0      ; Y
            .byte   0x90,0x28      ; Z

            .end