;   Built with Code Composer Studio V20.4
;******************************************************************************
;   Description: Blinks the Green LED 3 times, then the Red LED 2 times.
;                This sequence repeats indefinitely.
;******************************************************************************
            .cdecls C,LIST,"msp430fr6989.h"

            .text
            .global main

main:
            ; 1. Disable the Watchdog Timer 
            ; Prevents the microcontroller from resetting during execution
            mov.w   #WDTPW|WDTHOLD, &WDTCTL

            ; 2. Unlock GPIO (General Purpose Input/Output)
            ; Required for the MSP430FRxxxx framing to activate pins after boot
            bic.w   #LOCKLPM5, &PM5CTL0

            ; 3. Configure LED Pins
            ; Set P1.0 (Red LED) as an output and initialize to OFF (0)
            bis.b   #BIT0, &P1DIR
            bic.b   #BIT0, &P1OUT

            ; Set P9.7 (Green LED) as an output and initialize to OFF (0)
            bis.b   #BIT7, &P9DIR
            bic.b   #BIT7, &P9OUT

; -----------------------------------------------------------------------------
; Main Execution Loop
; -----------------------------------------------------------------------------
MAIN_LOOP:
            ; --- Phase 1: Green LED Blinks (3 Times) ---
            mov     #3, R4          ; Load loop counter with 3
GREEN_LOOP:
            bis.b   #BIT7, &P9OUT   ; Turn Green LED ON
            calla   #DELAY          ; Wait
            bic.b   #BIT7, &P9OUT   ; Turn Green LED OFF
            calla   #DELAY          ; Wait
            dec     R4              ; Decrement the loop counter
            jnz     GREEN_LOOP      ; If counter != 0, repeat the green blink

            ; --- Phase 2: Red LED Blinks (2 Times) ---
            mov     #2, R4          ; Load loop counter with 2
RED_LOOP:
            bis.b   #BIT0, &P1OUT   ; Turn Red LED ON
            calla   #DELAY          ; Wait
            bic.b   #BIT0, &P1OUT   ; Turn Red LED OFF
            calla   #DELAY          ; Wait
            dec     R4              ; Decrement the loop counter
            jnz     RED_LOOP        ; If counter != 0, repeat the red blink
            
            ; --- Phase 3: Repeat Sequence ---
            jmp     MAIN_LOOP       ; Jump back to the top of the sequence

; -----------------------------------------------------------------------------
; Subroutines
; -----------------------------------------------------------------------------
DELAY:
            ; Software delay loop to create a visible pause
            mov     #50000, R5      ; Load delay counter
D1:
            dec     R5              ; Decrement counter
            jnz     D1              ; Loop until counter reaches 0
            reta                    ; Return to the calling loop