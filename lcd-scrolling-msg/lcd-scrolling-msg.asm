;******************************************************************************
; Project: LCD Scrolling Message Marquee
; Hardware: MSP430FR6989 LaunchPad
; Description: Scrolls a custom message continuously across the 6-character 
;              LaunchPad LCD. The scrolling updates every 0.5 seconds using a 
;              Timer interrupt. Pressing the Left or Right buttons changes 
;              the direction of the scrolling text.
;******************************************************************************
            .cdecls C,LIST,"msp430.h"
            .def    RESET
            .global __STACK_END
            .sect   .stack

; -----------------------------------------------------------------------------
; 14-Segment LCD Hex Definitions
; -----------------------------------------------------------------------------
; High byte segments
SEGA        .set    1000000000000000b
SEGB        .set    0100000000000000b
SEGC        .set    0010000000000000b
SEGD        .set    0001000000000000b
SEGE        .set    0000100000000000b
SEGF        .set    0000010000000000b
SEGG        .set    0000001000000000b
SEGM        .set    0000000100000000b

; Low byte segments
SEGH        .set    0000000010000000b
SEGJ        .set    0000000001000000b
SEGK        .set    0000000000100000b
SEGP        .set    0000000000010000b
SEGQ        .set    0000000000001000b
SEGN        .set    0000000000000010b
SEGDP       .set    0000000000000001b

; -----------------------------------------------------------------------------
; Hardware Constants & Game Rules
; -----------------------------------------------------------------------------
BTN_LEFT        .set    BIT1            ; P1.1 (LaunchPad Left Button)
BTN_RIGHT       .set    BIT2            ; P1.2 (LaunchPad Right Button)

DIR_R2L         .set    0               ; Scroll Right-to-Left
DIR_L2R         .set    1               ; Scroll Left-to-Right

VISIBLE_CHARS   .set    6               ; LCD has 6 character slots
MSG_LEN         .set    48              ; Total message length including padding

; -----------------------------------------------------------------------------
; Data Memory (RAM)
; -----------------------------------------------------------------------------
            .bss    StartIndex, 2       ; Tracks which character is at the far left of the LCD
            .bss    Direction, 2        ; Current scrolling direction state

; -----------------------------------------------------------------------------
; Initialization & Main Loop
; -----------------------------------------------------------------------------
            .text
            .retain
            .retainrefs

RESET:
            mov.w   #__STACK_END, SP            ; Initialize Stack Pointer
            mov.w   #WDTPW|WDTHOLD, &WDTCTL     ; Stop watchdog timer

; LaunchPad Segment LCD Peripheral Setup
            mov.w   #1111111111000000b, &LCDCPCTL0
            mov.w   #1111000000111111b, &LCDCPCTL1
            mov.w   #0000000011110000b, &LCDCPCTL2

            bis.w   #LCDPRE__16+LCD4MUX, &LCDCCTL0
            bis.w   #LCDCLRM, &LCDCMEMCTL
            bis.w   #LCDON, &LCDCCTL0

            bic.w   #LOCKLPM5, &PM5CTL0         ; Unlock GPIO

; Button Setup: P1.1 and P1.2 with pullups and interrupts
            bic.b   #BTN_LEFT|BTN_RIGHT, &P1DIR ; Set as Inputs
            bis.b   #BTN_LEFT|BTN_RIGHT, &P1REN ; Enable Resistors
            bis.b   #BTN_LEFT|BTN_RIGHT, &P1OUT ; Pull-Up
            bis.b   #BTN_LEFT|BTN_RIGHT, &P1IES ; Trigger on falling edge (press)
            bic.b   #BTN_LEFT|BTN_RIGHT, &P1IFG ; Clear interrupt flags
            bis.b   #BTN_LEFT|BTN_RIGHT, &P1IE  ; Enable interrupts for pins

; Timer_A0 Setup: Triggers scroll updates
; ACLK runs at 32768 Hz. We want a 0.5s tick.
; 32768 / 2 = 16384 counts. CCR0 is zero-indexed, so 16383.
            mov.w   #CCIE, &TA0CCTL0            ; Enable capture/compare interrupt
            mov.w   #16383, &TA0CCR0            ; 0.5 second interval
            mov.w   #TASSEL__ACLK|MC__UP|TACLR, &TA0CTL ; ACLK source, Up mode

; Initial RAM State
            mov.w   #0, &StartIndex             ; Start at beginning of message
            mov.w   #DIR_R2L, &Direction        ; Default to scrolling right-to-left

            call    #ClearLCD
            call    #RenderWindow

; CPU Sleep Loop: Everything is driven by interrupts now
Sleep:
            nop
            bis.w   #LPM3|GIE, SR               ; Enter Low-Power Mode 3 + Global Interrupts
            nop
            jmp     Sleep

; -----------------------------------------------------------------------------
; Subroutines
; -----------------------------------------------------------------------------
; Wipes the LCD memory registers
ClearLCD:
            clr.b   &LCDM10
            clr.b   &LCDM11
            clr.b   &LCDM6
            clr.b   &LCDM7
            clr.b   &LCDM4
            clr.b   &LCDM5
            clr.b   &LCDM19
            clr.b   &LCDM20
            clr.b   &LCDM15
            clr.b   &LCDM16
            clr.b   &LCDM8
            clr.b   &LCDM9
            ret

; Helper to write to specific LCD digits based on jump table math
; Inputs:
;   R15 = character offset into CHAR table
;   R14 = jump-table digit offset (0,2,4,6,8,10)
LCDWrite:
            mov.w   CHAR(R15), R13          ; Fetch hex pattern for the character
            add.w   R14, PC                 ; Jump directly to the correct Digit block below

            jmp     LCDDig1                 ; Offset 0
            jmp     LCDDig2                 ; Offset 2
            jmp     LCDDig3                 ; Offset 4
            jmp     LCDDig4                 ; Offset 6
            jmp     LCDDig5                 ; Offset 8
            jmp     LCDDig6                 ; Offset 10

LCDDig1:
            mov.b   R13, &LCDM11
            swpb    R13
            mov.b   R13, &LCDM10
            ret

LCDDig2:
            mov.b   R13, &LCDM7
            swpb    R13
            mov.b   R13, &LCDM6
            ret

LCDDig3:
            mov.b   R13, &LCDM5
            swpb    R13
            mov.b   R13, &LCDM4
            ret

LCDDig4:
            mov.b   R13, &LCDM20
            swpb    R13
            mov.b   R13, &LCDM19
            ret

LCDDig5:
            mov.b   R13, &LCDM16
            swpb    R13
            mov.b   R13, &LCDM15
            ret

LCDDig6:
            mov.b   R13, &LCDM9
            swpb    R13
            mov.b   R13, &LCDM8
            ret

; Reads 6 characters from the MESSAGE array starting at StartIndex
; Handles wrapping around to the start of the array if it hits the end
RenderWindow:
            push.w  R4
            push.w  R5
            push.w  R14
            push.w  R15

            mov.w   #0, R4                  ; R4 = LCD position counter (0 to 5)

RenderLoop:
            mov.w   &StartIndex, R5
            add.w   R4, R5                  ; Calculate current message index

WrapCheck:
            cmp.w   #MSG_LEN, R5            ; Did we scroll past the end of the array?
            jl      IndexReady
            sub.w   #MSG_LEN, R5            ; If so, wrap back around to the beginning (modulo math)
            jmp     WrapCheck

IndexReady:
            add.w   R5, R5                  ; Multiply by 2 (Word array offset)
            mov.w   MESSAGE(R5), R15        ; Fetch offset mapping for the specific character

            mov.w   R4, R14
            add.w   R14, R14                ; Calculate Jump Table Offset (0, 2, 4, 6, 8, 10)
            call    #LCDWrite

            inc.w   R4                      ; Move to next LCD slot
            cmp.w   #VISIBLE_CHARS, R4
            jl      RenderLoop

            pop.w   R15                     ; Restore stack
            pop.w   R14
            pop.w   R5
            pop.w   R4
            ret

; Shifts the viewing window left or right based on Direction state
AdvanceScroll:
            cmp.w   #DIR_R2L, &Direction
            jne     MoveL2R

; Handle Right-to-Left scrolling
            inc.w   &StartIndex
            cmp.w   #MSG_LEN, &StartIndex
            jl      AdvanceDone
            mov.w   #0, &StartIndex         ; Wrap window back to 0
            ret

; Handle Left-to-Right scrolling
MoveL2R:
            tst.w   &StartIndex             ; Are we already at index 0?
            jnz     DecOK
            mov.w   #MSG_LEN-1, &StartIndex ; Wrap window to end of array
            ret

DecOK:
            dec.w   &StartIndex

AdvanceDone:
            ret

; Simple software delay to wait out physical button bouncing
Debounce:
            mov.w   #6000, R12
DB_Loop:
            dec.w   R12
            jnz     DB_Loop
            ret

; -----------------------------------------------------------------------------
; Interrupt Service Routines
; -----------------------------------------------------------------------------
; Triggered every 0.5s by Timer A0
TIMER0_A0_ISR:
            bic.w   #LPM3, 0(SP)            ; Wake up CPU
            call    #RenderWindow           ; Draw current frame
            call    #AdvanceScroll          ; Shift window for NEXT frame
            reti

; Triggered when Left or Right buttons are pressed
PORT1_ISR:
            bic.w   #LPM3, 0(SP)            ; Wake up CPU
            call    #Debounce

            bit.b   #BTN_LEFT, &P1IFG       ; Was Left Button pressed?
            jz      CheckRight
            mov.w   #DIR_R2L, &Direction    ; Change direction
            bic.b   #BTN_LEFT, &P1IFG       ; Clear flag

CheckRight:
            bit.b   #BTN_RIGHT, &P1IFG      ; Was Right Button pressed?
            jz      PortDone
            mov.w   #DIR_L2R, &Direction    ; Change direction
            bic.b   #BTN_RIGHT, &P1IFG      ; Clear flag

PortDone:
            reti

; -----------------------------------------------------------------------------
; Constant Look-Up Tables
; -----------------------------------------------------------------------------
; Message Array: Mapped directly to character offsets in the CHAR table below
; The math ('Char' - ' ') * 2 dynamically calculates the memory offset.
MESSAGE:
            ; 6 Blank spaces for padding
            .word   (' '-' ')*2, (' '-' ')*2, (' '-' ')*2, (' '-' ')*2, (' '-' ')*2, (' '-' ')*2

            ; Payload
            .word   ('M'-' ')*2, ('D'-' ')*2, (' '-' ')*2, ('M'-' ')*2, ('A'-' ')*2, ('K'-' ')*2
            .word   ('S'-' ')*2, ('U'-' ')*2, ('D'-' ')*2, ('U'-' ')*2, ('L'-' ')*2, (' '-' ')*2
            .word   ('H'-' ')*2, ('A'-' ')*2, ('Q'-' ')*2, ('U'-' ')*2, ('E'-' ')*2, (' '-' ')*2
            .word   ('R'-' ')*2, ('I'-' ')*2, ('S'-' ')*2, ('H'-' ')*2, ('A'-' ')*2, ('D'-' ')*2
            .word   (' '-' ')*2, ('-'-' ')*2, (' '-' ')*2, ('R'-' ')*2, ('1'-' ')*2, ('2'-' ')*2
            .word   ('3'-' ')*2, ('4'-' ')*2, ('5'-' ')*2, ('6'-' ')*2, ('7'-' ')*2, ('8'-' ')*2

            ; 6 Blank spaces for padding tail
            .word   (' '-' ')*2, (' '-' ')*2, (' '-' ')*2, (' '-' ')*2, (' '-' ')*2, (' '-' ')*2

; Master Character Hex Table (Indexed from ASCII ' ' Space upward) [Only Mapped the required Letters, Map as you need]
CHAR:
            .word   0                                                   ; ' ' (Space)
            .word   0,0,0,0,0,0,0,0,0,0,0,0                             ; '!' through ','
            .word   SEGG                                                ; '-'
            .word   0,0                                                 ; '.' '/'
            .word   SEGA+SEGB+SEGC+SEGD+SEGE+SEGF+SEGQ+SEGK             ; '0'
            .word   SEGB+SEGC                                           ; '1'
            .word   SEGA+SEGB+SEGD+SEGE+SEGG+SEGM                       ; '2'
            .word   SEGA+SEGB+SEGC+SEGD+SEGM                            ; '3'
            .word   SEGF+SEGG+SEGM+SEGB+SEGC                            ; '4'
            .word   SEGA+SEGF+SEGG+SEGC+SEGD+SEGM                       ; '5'
            .word   SEGA+SEGF+SEGE+SEGD+SEGC+SEGG                       ; '6'
            .word   SEGA+SEGB+SEGC                                      ; '7'
            .word   SEGA+SEGB+SEGC+SEGD+SEGE+SEGF+SEGG                  ; '8'
            .word   SEGA+SEGB+SEGC+SEGD+SEGF+SEGG+SEGM                  ; '9'
            .word   0,0,0,0,0,0,0                                       ; ':' through '@'
            .word   SEGA+SEGB+SEGC+SEGE+SEGF+SEGG+SEGM                  ; 'A'
            .word   0                                                   ; 'B'
            .word   0                                                   ; 'C'
            .word   SEGA+SEGB+SEGC+SEGD+SEGE+SEGF                       ; 'D'
            .word   SEGA+SEGF+SEGG+SEGM+SEGE+SEGD                       ; 'E'
            .word   0                                                   ; 'F'
            .word   0                                                   ; 'G'
            .word   SEGB+SEGC+SEGE+SEGF+SEGG+SEGM                       ; 'H'
            .word   SEGA+SEGD+SEGJ+SEGP                                 ; 'I'
            .word   0                                                   ; 'J'
            .word   SEGE+SEGF+SEGG+SEGK+SEGN                            ; 'K'
            .word   SEGE+SEGF+SEGD                                      ; 'L'
            .word   SEGE+SEGF+SEGH+SEGK+SEGB+SEGC                       ; 'M'
            .word   SEGB+SEGC+SEGE+SEGF+SEGH+SEGN                       ; 'N'
            .word   0                                                   ; 'O'
            .word   0                                                   ; 'P'
            .word   SEGA+SEGB+SEGC+SEGD+SEGE+SEGF+SEGN                  ; 'Q'
            .word   SEGA+SEGB+SEGN+SEGE+SEGF+SEGG+SEGM                  ; 'R'
            .word   SEGA+SEGF+SEGG+SEGC+SEGD+SEGM                       ; 'S'
            .word   0                                                   ; 'T'
            .word   SEGF+SEGE+SEGD+SEGC+SEGB                            ; 'U'
            .word   0                                                   ; 'V'
            .word   SEGB+SEGC+SEGE+SEGF+SEGQ+SEGN                       ; 'W'
            .word   0                                                   ; 'X'
            .word   0                                                   ; 'Y'
            .word   0                                                   ; 'Z'

; -----------------------------------------------------------------------------
; Linker Directives
; -----------------------------------------------------------------------------
            .sect   TIMER0_A0_VECTOR
            .short  TIMER0_A0_ISR

            .sect   PORT1_VECTOR
            .short  PORT1_ISR

            .sect   ".reset"
            .short  RESET
            .end