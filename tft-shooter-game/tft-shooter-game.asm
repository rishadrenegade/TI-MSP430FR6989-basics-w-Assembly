;******************************************************************************
; Project: Crosshair Shooter Gallery
; Hardware: MSP430FR6989 + BOOSTXL-EDUMKII
; Description: Use the joystick to move a crosshair across the TFT display.
;              Press Button 1 to shoot targets before they expire. 
;              Hits flash Green, Misses flash Red. Reach score of 4 to win.
;******************************************************************************
            .cdecls C,LIST,"msp430.h"
            .text
            .global main

; -----------------------------------------------------------------------------
; LCD Segment Definitions for the LaunchPad's onboard display
; -----------------------------------------------------------------------------
SEGA        .set 1000000000000000b
SEGB        .set 0100000000000000b
SEGC        .set 0010000000000000b
SEGD        .set 0001000000000000b
SEGE        .set 0000100000000000b
SEGF        .set 0000010000000000b
SEGG        .set 0000001000000000b
SEGM        .set 0000000100000000b
SEGH        .set 0000000010000000b
SEGJ        .set 0000000001000000b
SEGK        .set 0000000000100000b
SEGP        .set 0000000000010000b
SEGQ        .set 0000000000001000b
SEGN        .set 0000000000000010b

; -----------------------------------------------------------------------------
; Hardware Macros for TFT Communication
; -----------------------------------------------------------------------------
delay       .macro  count
            mov #count, R15             ; Load delay counter
            dec R15                     ; Decrement
            jnz $-2                     ; Jump to previous instruction if not zero
            .endm

RST_HIGH    .macro                      ; Pull TFT Reset pin HIGH (Inactive)
            bis.b   #BIT4, &P9OUT
            .endm

RST_LOW     .macro                      ; Pull TFT Reset pin LOW (Active)
            bic.b   #BIT4, &P9OUT
            .endm

CS_HIGH     .macro                      ; Pull Chip Select HIGH (Deselect TFT)
            bis.b   #BIT5, &P2OUT
            .endm

CS_LOW      .macro                      ; Pull Chip Select LOW (Select TFT)
            bic.b   #BIT5, &P2OUT
            .endm

; Macro to send multiple bytes of pixel data to the TFT via SPI
send_data   .macro d0, d1, d2
            mov.b   d0, R15
            call    #tft_data_sr
            .if $symlen(":d1:") > 0
                    mov.b   d1, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d2:") > 0
                    mov.b   d2, R15
                    call    #tft_data_sr
            .endif
            .endm

; Macro to send a command address followed by varying amounts of configuration data
tft_config  .macro  address, d0, d1, d2, d3, d4, d5, d6, d7, d8, d9, d10, d11, d12, d13, d14, d15
            mov.b   #address, R15
            call    #tft_cmd_sr
            .if $symlen(":d0:") > 0
                    mov.b   d0, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d1:") > 0
                    mov.b   d1, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d2:") > 0
                    mov.b   d2, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d3:") > 0
                    mov.b   d3, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d4:") > 0
                    mov.b   d4, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d5:") > 0
                    mov.b   d5, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d6:") > 0
                    mov.b   d6, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d7:") > 0
                    mov.b   d7, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d8:") > 0
                    mov.b   d8, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d9:") > 0
                    mov.b   d9, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d10:") > 0
                    mov.b   d10, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d11:") > 0
                    mov.b   d11, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d12:") > 0
                    mov.b   d12, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d13:") > 0
                    mov.b   d13, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d14:") > 0
                    mov.b   d14, R15
                    call    #tft_data_sr
            .endif
            .if $symlen(":d15:") > 0
                    mov.b   d15, R15
                    call    #tft_data_sr
            .endif
            .endm

; -----------------------------------------------------------------------------
; Game Constants & Rules
; -----------------------------------------------------------------------------
TARGET_COUNT    .equ 8                  ; Total coordinate sets in spawn table
TARGET_LIFE     .equ 40                 ; Ticks a target stays active before disappearing
SPAWN_INTERVAL  .equ 30                 ; Ticks between new targets
FLASH_TICKS     .equ 5                  ; Ticks to flash RGB LED on hit/miss
WIN_SCORE       .equ 4                  ; Score required to trigger win state
SCORE_X_TENS    .equ 4                  ; X-coordinate for tens digit of score
SCORE_X_ONES    .equ 12                 ; X-coordinate for ones digit of score
SCORE_Y         .equ 4                  ; Y-coordinate for score

; -----------------------------------------------------------------------------
; Game State Variables (RAM)
; -----------------------------------------------------------------------------
            .bss CrosshairX, 2          ; Current X position of crosshair
            .bss CrosshairY, 2          ; Current Y position of crosshair
            .bss JoyX, 2                ; Raw ADC X value from joystick
            .bss JoyY, 2                ; Raw ADC Y value from joystick
            .bss TargetX, 2             ; Current X position of target
            .bss TargetY, 2             ; Current Y position of target
            .bss TargetActive, 2        ; Boolean flag: Is a target on screen?
            .bss TargetLife, 2          ; Countdown timer for target despawn
            .bss SpawnTimer, 2          ; Countdown timer for next spawn
            .bss TargetIndex, 2         ; Index tracking which table coordinate to use next
            .bss Score, 2               ; Current player score
            .bss FlashCounter, 2        ; LED Flash duration tracker
            .bss GameWon, 2             ; Boolean flag: Has the player won?

; -----------------------------------------------------------------------------
; Memory Lookup Tables
; -----------------------------------------------------------------------------
; Target spawn coordinates (X, Y)
TargetTable:
            .word   20, 20
            .word   100, 30
            .word   60, 50
            .word   30, 90
            .word   90, 80
            .word   15, 60
            .word   75, 15
            .word   110, 105

; 5x7 bitmap font hex arrays for digits 0-9
DigitTable:
            .byte   0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E  ; 0
            .byte   0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E  ; 1
            .byte   0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F  ; 2
            .byte   0x0E, 0x11, 0x01, 0x06, 0x01, 0x11, 0x0E  ; 3
            .byte   0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02  ; 4
            .byte   0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E  ; 5
            .byte   0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E  ; 6
            .byte   0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08  ; 7
            .byte   0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E  ; 8
            .byte   0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C  ; 9

; Segment patterns for the word "WINNER"
CHAR_TABLE:
            .word   SEGB+SEGC+SEGE+SEGF+SEGQ+SEGN           ; W
            .word   SEGA+SEGD+SEGJ+SEGP                     ; I
            .word   SEGB+SEGC+SEGE+SEGF+SEGH+SEGN           ; N
            .word   SEGB+SEGC+SEGE+SEGF+SEGH+SEGN           ; N
            .word   SEGA+SEGD+SEGE+SEGF+SEGG+SEGM           ; E
            .word   SEGA+SEGB+SEGE+SEGF+SEGG+SEGM+SEGN      ; R

; -----------------------------------------------------------------------------
; Main Initialization
; -----------------------------------------------------------------------------
main:
            mov.w   #WDTPW|WDTHOLD, &WDTCTL     ; Stop watchdog timer
            mov.w   #0x2400, SP                 ; Initialize stack pointer

            ; Clock System Setup (8MHz)
            mov.b   #CSKEY_H, &CSCTL0_H
            mov.w   #DCOFSEL_6, &CSCTL1
            mov.w   #SELA__VLOCLK+SELS__DCOCLK+SELM__DCOCLK, &CSCTL2
            mov.w   #DIVA__1+DIVS__1+DIVM__1, &CSCTL3
            clr.b   &CSCTL0_H

            ; TFT SPI Pins (MOSI, MISO, SCLK)
            bis.b   #BIT4+BIT6+BIT7, &P1SEL0
            bic.b   #BIT4+BIT6+BIT7, &P1SEL1

            ; TFT Reset Pin (P9.4)
            bis.b   #BIT4, &P9OUT
            bic.b   #BIT4, &P9OUT
            bis.b   #BIT4, &P9DIR

            ; TFT Chip Select (P2.5) and Data/Command (P2.3)
            bis.b   #BIT3+BIT5, &P2DIR

            ; RGB LED Output Configuration (Mapped to BoosterPack Pins)
            bis.b   #BIT6, &P2DIR
            bis.b   #BIT6+BIT3, &P3DIR
            bic.b   #BIT6, &P2OUT
            bic.b   #BIT6+BIT3, &P3OUT
            bic.b   #BIT6, &P2SEL1
            bis.b   #BIT6, &P2SEL0
            bis.b   #BIT6+BIT3, &P3SEL1
            bic.b   #BIT6+BIT3, &P3SEL0

            ; Timer A1 PWM setup (Green LED)
            bis.w   #TASSEL__SMCLK+MC__UP, &TA1CTL
            mov.w   #999, &TA1CCR0
            bis.w   #OUTMOD_7, &TA1CCTL1
            mov.w   #0, &TA1CCR1                  ; Duty cycle = 0 (OFF)

            ; Timer B0 PWM setup (Red and Blue LEDs)
            bis.w   #TBSSEL__SMCLK+MC__UP, &TB0CTL
            mov.w   #999, &TB0CCR0
            bis.w   #OUTMOD_7, &TB0CCTL2
            bis.w   #OUTMOD_7, &TB0CCTL5
            mov.w   #0, &TB0CCR2                  ; Red OFF
            mov.w   #0, &TB0CCR5                  ; Blue OFF

            ; Push Button Setup (Fire & Reset triggers)
            bic.b   #BIT0+BIT1, &P3DIR
            bis.b   #BIT0+BIT1, &P3REN
            bis.b   #BIT0+BIT1, &P3OUT
            bis.b   #BIT0+BIT1, &P3IES            ; Falling edge interrupts
            bic.b   #BIT0+BIT1, &P3IFG
            bis.b   #BIT0+BIT1, &P3IE

            ; LaunchPad LCD Peripheral Initialization
            mov.w   #1111111111000000b, &LCDCPCTL0
            mov.w   #1111000000111111b, &LCDCPCTL1
            mov.w   #0000000011110000b, &LCDCPCTL2
            bis.w   #LCDPRE__16+LCD4MUX, &LCDCCTL0
            bis.w   #LCDCLRM, &LCDCMEMCTL
            bis.w   #LCDON, &LCDCCTL0

            ; eUSCI_B0 SPI Master Initialization
            mov.w   #UCSWRST, &UCB0CTLW0
            bis.w   #UCSSEL__SMCLK+UCSYNC+UCMODE_0+UCMST+UCMSB, &UCB0CTLW0
            mov.w   #2, &UCB0BRW
            bic.w   #UCSWRST, &UCB0CTLW0

            bic.w   #LOCKLPM5, &PM5CTL0           ; Unlock GPIO

            ; TFT Hardware Reset Pulse
            RST_LOW
            delay   1000
            RST_HIGH
            delay   60000
            delay   60000

            ; ST7735 TFT Boot Configuration Sequence
            tft_config  0x11
            delay   60000
            delay   60000
            tft_config  0xB1,#0x02,#0x35,#0x36
            tft_config  0xB2,#0x02,#0x35,#0x36
            tft_config  0xB3,#0x02,#0x35,#0x36,#0x02,#0x35,#0x36
            tft_config  0xB4,#0x07
            tft_config  0xC0,#0x02,#0x02
            tft_config  0xC1,#0xC5
            tft_config  0xC2,#0x0D,#0x00
            tft_config  0xC3,#0x8D,#0x1A
            tft_config  0xC4,#0x8D,#0xEE
            tft_config  0xC5,#0x51,#0x4D
            tft_config  0xE0,#0x0A,#0x1C,#0x0C,#0x14,#0x33,#0x2B,#0x24,#0x28,#0x27,#0x25,#0x2C,#0x39,#0x00,#0x05,#0x03,#0x0D
            tft_config  0xE1,#0x0A,#0x1C,#0x0C,#0x14,#0x33,#0x2B,#0x24,#0x28,#0x27,#0x25,#0x2C,#0x39,#0x00,#0x05,#0x03,#0x0D
            tft_config  0x3A,#0x06
            tft_config  0x29
            delay   1000
            tft_config  0x36,#0x40

            call    #FillScreenBlue

            ; Initialize starting state for gameplay variables
            mov.w   #62, &CrosshairX            ; Center screen (128x128)
            mov.w   #62, &CrosshairY
            mov.w   #2048, &JoyX                ; Center ADC value (12-bit is 0-4095)
            mov.w   #2048, &JoyY
            mov.w   #0, &TargetActive
            mov.w   #0, &TargetLife
            mov.w   #SPAWN_INTERVAL, &SpawnTimer
            mov.w   #0, &TargetIndex
            mov.w   #0, &Score
            mov.w   #0, &FlashCounter
            mov.w   #0, &GameWon

            call    #DrawCrosshair
            call    #DrawScore

            ; ADC12 Configuration for Joystick X/Y Reading
            mov.w   #ADC12SHT0_2|ADC12ON|ADC12MSC, &ADC12CTL0
            bis.w   #ADC12SHP|ADC12CONSEQ_3, &ADC12CTL1
            bis.w   #ADC12RES_2, &ADC12CTL2
            bis.w   #ADC12INCH_10, &ADC12MCTL0
            bis.w   #ADC12INCH_4, &ADC12MCTL1
            bis.w   #ADC12IE0|ADC12IE1, &ADC12IER0
            bis.w   #ADC12ENC|ADC12SC, &ADC12CTL0 ; Start sampling

            ; Timer A0: Master Game Tick (50ms interrupts)
            mov.w   #1638, &TA0CCR0
            bis.w   #CCIE, &TA0CCTL0
            mov.w   #TASSEL_1|MC_1|TACLR, &TA0CTL

            nop
            bis.w   #LPM0|GIE, SR               ; CPU sleeps, woken by interrupts
            nop

; -----------------------------------------------------------------------------
; Core Drawing Subroutines
; -----------------------------------------------------------------------------
; Pushes a dark blue block across the entire display buffer
FillScreenBlue:
            tft_config  0x2A,#0x00,#0x02,#0x00,#0x81
            tft_config  0x2B,#0x00,#0x01,#0x00,#0x80
            tft_config  0x2C
            mov.w   #16384, R12                 ; 128x128 pixels
FillBlueLoop:
            send_data #0x80, #0x00, #0x00       ; R, G, B
            dec.w   R12
            jnz     FillBlueLoop
            ret

; Paints the crosshair pixels over with the background color to erase it
EraseCrosshair:
            ; Set X bounds
            mov.b   #0x2A, R15
            call    #tft_cmd_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &CrosshairX, R14
            add.w   #2, R14                     ; Box width offset
            mov.b   R14, R15
            call    #tft_data_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &CrosshairX, R14
            add.w   #5, R14
            mov.b   R14, R15
            call    #tft_data_sr

            ; Set Y bounds
            mov.b   #0x2B, R15
            call    #tft_cmd_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &CrosshairY, R14
            add.w   #1, R14
            mov.b   R14, R15
            call    #tft_data_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &CrosshairY, R14
            add.w   #4, R14
            mov.b   R14, R15
            call    #tft_data_sr

            ; Command to write pixels to bound box
            mov.b   #0x2C, R15
            call    #tft_cmd_sr

            mov.w   #16, R12                    ; 4x4 box = 16 pixels
EraseLoop:
            send_data #0x80, #0x00, #0x00       ; Write Background color
            dec.w   R12
            jnz     EraseLoop
            ret

; Draws the 4x4 white player crosshair at updated coordinates
DrawCrosshair:
            mov.b   #0x2A, R15
            call    #tft_cmd_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &CrosshairX, R14
            add.w   #2, R14
            mov.b   R14, R15
            call    #tft_data_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &CrosshairX, R14
            add.w   #5, R14
            mov.b   R14, R15
            call    #tft_data_sr

            mov.b   #0x2B, R15
            call    #tft_cmd_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &CrosshairY, R14
            add.w   #1, R14
            mov.b   R14, R15
            call    #tft_data_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &CrosshairY, R14
            add.w   #4, R14
            mov.b   R14, R15
            call    #tft_data_sr

            mov.b   #0x2C, R15
            call    #tft_cmd_sr

            mov.w   #16, R12
DrawLoop:
            send_data #0xFF, #0xFF, #0xFF       ; White pixel
            dec.w   R12
            jnz     DrawLoop
            ret

; Draws a 6x6 red target block based on the TargetX/Y variables
DrawTarget:
            mov.b   #0x2A, R15
            call    #tft_cmd_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &TargetX, R14
            add.w   #2, R14
            mov.b   R14, R15
            call    #tft_data_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &TargetX, R14
            add.w   #7, R14
            mov.b   R14, R15
            call    #tft_data_sr

            mov.b   #0x2B, R15
            call    #tft_cmd_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &TargetY, R14
            add.w   #1, R14
            mov.b   R14, R15
            call    #tft_data_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &TargetY, R14
            add.w   #6, R14
            mov.b   R14, R15
            call    #tft_data_sr

            mov.b   #0x2C, R15
            call    #tft_cmd_sr

            mov.w   #36, R12                    ; 6x6 target = 36 pixels
TargetDrawLoop:
            send_data #0x00, #0x00, #0xFF       ; Red pixel (BGR)
            dec.w   R12
            jnz     TargetDrawLoop
            ret

EraseTarget:
            mov.b   #0x2A, R15
            call    #tft_cmd_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &TargetX, R14
            add.w   #2, R14
            mov.b   R14, R15
            call    #tft_data_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &TargetX, R14
            add.w   #7, R14
            mov.b   R14, R15
            call    #tft_data_sr

            mov.b   #0x2B, R15
            call    #tft_cmd_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &TargetY, R14
            add.w   #1, R14
            mov.b   R14, R15
            call    #tft_data_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   &TargetY, R14
            add.w   #6, R14
            mov.b   R14, R15
            call    #tft_data_sr

            mov.b   #0x2C, R15
            call    #tft_cmd_sr

            mov.w   #36, R12
TargetEraseLoop:
            send_data #0x80, #0x00, #0x00       ; Replace with Background color
            dec.w   R12
            jnz     TargetEraseLoop
            ret

; -----------------------------------------------------------------------------
; Game Logic Math
; -----------------------------------------------------------------------------
; Grabs the next coordinate pair from the target lookup table
SpawnTarget:
            mov.w   &TargetIndex, R6
            rla.w   R6                          ; Multiply index by 4 (Words are 2 bytes)
            rla.w   R6                          ; Offset for word table array
            mov.w   TargetTable(R6), &TargetX
            mov.w   TargetTable+2(R6), &TargetY
            inc.w   &TargetIndex
            cmp.w   #TARGET_COUNT, &TargetIndex ; Reset index if at end of table
            jl      SpawnDone
            mov.w   #0, &TargetIndex
SpawnDone:
            mov.w   #1, &TargetActive           ; Mark target live
            mov.w   #TARGET_LIFE, &TargetLife   ; Reset despawn counter
            call    #DrawTarget
            ret

; AABB Collision Detection algorithm (Axis-Aligned Bounding Box)
CheckHit:
            mov.w   #0, R7                      ; Assume miss (R7 = 0)
            cmp.w   #0, &TargetActive           ; Can't hit if nothing is there
            jeq     HitDone

            ; Check if Crosshair right edge < Target left edge
            mov.w   &CrosshairX, R8
            add.w   #4, R8
            cmp.w   &TargetX, R8
            jl      HitDone
            jeq     HitDone

            ; Check if Target right edge < Crosshair left edge
            mov.w   &TargetX, R9
            add.w   #6, R9
            cmp.w   R9, &CrosshairX
            jge     HitDone

            ; Check if Crosshair bottom edge < Target top edge
            mov.w   &CrosshairY, R8
            add.w   #4, R8
            cmp.w   &TargetY, R8
            jl      HitDone
            jeq     HitDone

            ; Check if Target bottom edge < Crosshair top edge
            mov.w   &TargetY, R9
            add.w   #6, R9
            cmp.w   R9, &CrosshairY
            jge     HitDone

            mov.w   #1, R7                      ; Both axes overlap -> Hit! (R7 = 1)
HitDone:
            ret

; -----------------------------------------------------------------------------
; LED Status Feedback
; -----------------------------------------------------------------------------
LEDOff:
            mov.w   #0, &TB0CCR5
            mov.w   #0, &TA1CCR1
            mov.w   #0, &TB0CCR2
            ret

LEDGreen:
            mov.w   #0, &TB0CCR5
            mov.w   #999, &TA1CCR1
            mov.w   #0, &TB0CCR2
            mov.w   #FLASH_TICKS, &FlashCounter
            ret

LEDGreenLocked:
            mov.w   #0, &TB0CCR5
            mov.w   #999, &TA1CCR1
            mov.w   #0, &TB0CCR2
            mov.w   #0, &FlashCounter          ; Disable flash decrementor to lock it on
            ret

LEDRed:
            mov.w   #999, &TB0CCR5
            mov.w   #0, &TA1CCR1
            mov.w   #0, &TB0CCR2
            mov.w   #FLASH_TICKS, &FlashCounter
            ret

; -----------------------------------------------------------------------------
; Display / UI Subroutines
; -----------------------------------------------------------------------------
; Maps pre-calculated Hex values to multiplexed LCD control registers
DisplayWinner:
            mov.w   CHAR_TABLE, R13
            mov.b   R13, &LCDM11
            swpb    R13
            mov.b   R13, &LCDM10

            mov.w   CHAR_TABLE+2, R13
            mov.b   R13, &LCDM7
            swpb    R13
            mov.b   R13, &LCDM6

            mov.w   CHAR_TABLE+4, R13
            mov.b   R13, &LCDM5
            swpb    R13
            mov.b   R13, &LCDM4

            mov.w   CHAR_TABLE+6, R13
            mov.b   R13, &LCDM20
            swpb    R13
            mov.b   R13, &LCDM19

            mov.w   CHAR_TABLE+8, R13
            mov.b   R13, &LCDM16
            swpb    R13
            mov.b   R13, &LCDM15

            mov.w   CHAR_TABLE+10, R13
            mov.b   R13, &LCDM9
            swpb    R13
            mov.b   R13, &LCDM8
            ret

ClearLCD:
            mov.b   #0, &LCDM11
            mov.b   #0, &LCDM10
            mov.b   #0, &LCDM7
            mov.b   #0, &LCDM6
            mov.b   #0, &LCDM5
            mov.b   #0, &LCDM4
            mov.b   #0, &LCDM20
            mov.b   #0, &LCDM19
            mov.b   #0, &LCDM16
            mov.b   #0, &LCDM15
            mov.b   #0, &LCDM9
            mov.b   #0, &LCDM8
            ret

; Renders custom bitmap font from memory onto the TFT
DrawDigit:
            mov.w   R6, R10                     ; Base offset calculation
            rla.w   R10
            rla.w   R10
            add.w   R6, R10                     ; Offset logic to find correct char block
            add.w   R6, R10
            add.w   R6, R10

            mov.w   #DigitTable, R11            ; Table starting address
            add.w   R10, R11                    ; Seek to target char

            ; Setup boundary box for character block
            mov.b   #0x2A, R15
            call    #tft_cmd_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   R8, R14
            add.w   #2, R14
            mov.b   R14, R15
            call    #tft_data_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   R8, R14
            add.w   #6, R14
            mov.b   R14, R15
            call    #tft_data_sr

            mov.b   #0x2B, R15
            call    #tft_cmd_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   R9, R14
            add.w   #1, R14
            mov.b   R14, R15
            call    #tft_data_sr
            mov.b   #0x00, R15
            call    #tft_data_sr
            mov.w   R9, R14
            add.w   #7, R14
            mov.b   R14, R15
            call    #tft_data_sr

            mov.b   #0x2C, R15
            call    #tft_cmd_sr

            mov.w   #7, R12                     ; Number of rows in font bitmap
RowLoop:
            mov.b   @R11+, R13                  ; Load row data

            ; Read bits to draw text layer vs background layer
            bit.b   #0x01, R13
            jz      Pix0Off
            send_data #0xFF, #0xFF, #0xFF
            jmp     Pix1
Pix0Off:
            send_data #0x80, #0x00, #0x00
Pix1:
            bit.b   #0x02, R13
            jz      Pix1Off
            send_data #0xFF, #0xFF, #0xFF
            jmp     Pix2
Pix1Off:
            send_data #0x80, #0x00, #0x00
Pix2:
            bit.b   #0x04, R13
            jz      Pix2Off
            send_data #0xFF, #0xFF, #0xFF
            jmp     Pix3
Pix2Off:
            send_data #0x80, #0x00, #0x00
Pix3:
            bit.b   #0x08, R13
            jz      Pix3Off
            send_data #0xFF, #0xFF, #0xFF
            jmp     Pix4
Pix3Off:
            send_data #0x80, #0x00, #0x00
Pix4:
            bit.b   #0x10, R13
            jz      Pix4Off
            send_data #0xFF, #0xFF, #0xFF
            jmp     RowDone
Pix4Off:
            send_data #0x80, #0x00, #0x00
RowDone:
            dec.w   R12
            jnz     RowLoop
            ret

; Extracts Tens and Ones places from raw Score integer to draw to screen
DrawScore:
            mov.w   &Score, R5
            cmp.w   #99, R5                     ; Cap score display to 99 max
            jl      ScoreOK
            mov.w   #99, R5
ScoreOK:
            mov.w   #0, R6
TensLoop:                                       ; Modulo math to find Tens place
            cmp.w   #10, R5
            jl      TensDone
            sub.w   #10, R5
            inc.w   R6
            jmp     TensLoop
TensDone:
            push.w  R5
            push.w  R6
            mov.w   #SCORE_X_ONES, R8           ; Send Ones coordinate offset
            mov.w   #SCORE_Y, R9
            call    #DrawDigit
            pop.w   R6
            pop.w   R5

            mov.w   R5, R6
            mov.w   #SCORE_X_TENS, R8           ; Send Tens coordinate offset
            mov.w   #SCORE_Y, R9
            call    #DrawDigit
            ret

; -----------------------------------------------------------------------------
; SPI Communications
; -----------------------------------------------------------------------------
tft_cmd_sr:
            CS_LOW
            bic.b   #BIT3, &P2OUT               ; DC Pin Low = Command
            call    #spi_byte
            CS_HIGH
            ret

tft_data_sr:
            CS_LOW
            bis.b   #BIT3, &P2OUT               ; DC Pin High = Data
            call    #spi_byte
            CS_HIGH
            ret

spi_byte:
spiT1:
            bit.w   #UCTXIFG, &UCB0IFG          ; Wait until buffer is ready
            jz      spiT1
            mov.b   R15, &UCB0TXBUF
spiT2:
            bit.w   #UCBUSY, &UCB0STATW         ; Wait until shift register is empty
            jnz     spiT2
            ret

; -----------------------------------------------------------------------------
; Interrupt Service Routines
; -----------------------------------------------------------------------------
; Game Tick ISR - Drives entity movement, despawns, and LED flash timing
            .sect ".text:_isr"
            .retain
TimerA0_ISR:
            cmp.w   #1, &GameWon                ; Freeze game tick loop if player won
            jeq     TimerExit

            ; Handle RGB LED flash duration
            cmp.w   #0, &FlashCounter
            jeq     SkipFlashTick
            dec.w   &FlashCounter
            jnz     SkipFlashTick
            call    #LEDOff

SkipFlashTick:
            call    #EraseCrosshair             ; Wipe old frame

            ; Joystick X-Axis Processing
            mov.w   &JoyX, R5
            sub.w   #2048, R5                   ; Normalize reading against center voltage
            cmp.w   #256, R5                    ; Deadzone calculation
            jge     XMoveRight
            cmp.w   #-256, R5
            jl      XMoveLeft
            jmp     UpdateY

XMoveRight:
            ; Math division by 256 via bit shift to determine movement speed modifier
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            add.w   R5, &CrosshairX
            cmp.w   #123, &CrosshairX           ; Screen boundary lock
            jl      CheckXLow
            mov.w   #123, &CrosshairX
            jmp     UpdateY
CheckXLow:
            cmp.w   #0, &CrosshairX
            jge     UpdateY
            mov.w   #0, &CrosshairX
            jmp     UpdateY

XMoveLeft:
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            add.w   R5, &CrosshairX
            cmp.w   #0, &CrosshairX             ; Screen boundary lock
            jge     UpdateY
            mov.w   #0, &CrosshairX

UpdateY:
            ; Joystick Y-Axis Processing
            mov.w   &JoyY, R5
            sub.w   #2048, R5                   ; Normalize reading against center voltage
            cmp.w   #256, R5                    ; Deadzone calculation
            jge     YMoveUp
            cmp.w   #-256, R5
            jl      YMoveDown
            jmp     UpdateDone

YMoveUp:
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            add.w   R5, &CrosshairY
            cmp.w   #123, &CrosshairY
            jl      UpdateDone
            mov.w   #123, &CrosshairY
            jmp     UpdateDone

YMoveDown:
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            rra.w   R5
            add.w   R5, &CrosshairY
            cmp.w   #0, &CrosshairY
            jge     UpdateDone
            mov.w   #0, &CrosshairY

UpdateDone:
            ; Entity Despawn Logic
            cmp.w   #0, &TargetActive
            jeq     CheckSpawn

            dec.w   &TargetLife                 ; Tick down target lifespan
            jnz     RedrawTarget

            call    #EraseTarget                ; Life expired > wipe target
            mov.w   #0, &TargetActive
            jmp     CheckSpawn

RedrawTarget:
            call    #DrawTarget

CheckSpawn:
            ; Entity Respawn Logic
            dec.w   &SpawnTimer
            jnz     DrawAndExit

            cmp.w   #0, &TargetActive
            jeq     DoSpawn
            call    #EraseTarget

DoSpawn:
            call    #SpawnTarget                ; Fetch next from table
            mov.w   #SPAWN_INTERVAL, &SpawnTimer; Reset timer

DrawAndExit:
            call    #DrawCrosshair              ; Draw new frame

TimerExit:
            reti

; Analog to Digital Converter ISR - Pulls X/Y coordinates directly into variables
            .sect ".text:_isr"
            .retain
ADC12_ISR:
            add.w   &ADC12IV, PC                ; Interrupt Vector math to find channel
            reti
            reti
            reti
            reti
            reti
            reti
            jmp     MEM0
            jmp     MEM1
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti
            reti

MEM0:
            mov.w   &ADC12MEM0, &JoyX           ; Commit X value
            reti
MEM1:
            mov.w   &ADC12MEM1, &JoyY           ; Commit Y value
            reti

; Handles Trigger pulls (Button 0) and Game Resets (Button 1)
            .sect ".text:_isr"
            .retain
Port3_ISR:
            mov.b   &P3IFG, R10
            bic.b   #BIT0+BIT1, &P3IFG          ; Clear interrupt flag

            cmp.w   #1, &GameWon
            jne     CheckShoot

            bit.b   #BIT1, R10                  ; If game is won, only allow Reset button
            jz      P3Done
            jmp     DoReset

CheckShoot:
            bit.b   #BIT0, R10                  ; Button 0 triggered?
            jz      CheckResetNormal

            call    #CheckHit                   ; Run AABB collision algorithm
            cmp.w   #0, R7
            jeq     ShotMissed

            ; Target Hit!
            call    #EraseTarget
            mov.w   #0, &TargetActive           ; Free up spawn status
            inc.w   &Score
            call    #LEDGreen                   ; Flash Green
            call    #DrawScore

            cmp.w   #WIN_SCORE, &Score          ; Check Win Condition
            jl      P3Done
            mov.w   #1, &GameWon
            call    #DisplayWinner              ; Post to LaunchPad LCD
            call    #LEDGreenLocked             ; Lock RGB state
            jmp     P3Done

ShotMissed:
            call    #LEDRed                     ; Flash Red
            jmp     P3Done

CheckResetNormal:
            bit.b   #BIT1, R10                  ; Button 1 triggered?
            jz      P3Done

DoReset:
            ; Wipe hardware and reset variables back to boot state
            call    #FillScreenBlue
            call    #ClearLCD
            mov.w   #62, &CrosshairX
            mov.w   #62, &CrosshairY
            mov.w   #0, &TargetActive
            mov.w   #0, &TargetLife
            mov.w   #SPAWN_INTERVAL, &SpawnTimer
            mov.w   #0, &TargetIndex
            mov.w   #0, &Score
            mov.w   #0, &FlashCounter
            mov.w   #0, &GameWon
            call    #LEDOff
            call    #DrawCrosshair
            call    #DrawScore

P3Done:
            reti

; -----------------------------------------------------------------------------
; Interrupt Linker Tables
; -----------------------------------------------------------------------------
            .sect   ".int44"                    ; Timer A0
            .retain
            .short  TimerA0_ISR
            .sect   ADC12_VECTOR                ; ADC12
            .retain
            .short  ADC12_ISR
            .sect   PORT3_VECTOR                ; Port 3 (Buttons)
            .retain
            .short  Port3_ISR
            .end