;******************************************************************************
; Project: Hold-to-Blink Controller (Polling / No Interrupts)
; Hardware: MSP430FR6989 LaunchPad
; Description: 
;   - Continuously polls both the Left and Right buttons.
;   - If BOTH buttons are held down for exactly 3 seconds, both the Red 
;     and Green LEDs begin to blink simultaneously.
;   - If either button is released before 3 seconds, the timer resets.
;   - If either button is released while blinking, the LEDs turn off 
;     and the system returns to the idle state.
;******************************************************************************
            .cdecls C,LIST,"msp430.h"

; -----------------------------------------------------------------------------
; Hardware Constants & Timing Variables
; -----------------------------------------------------------------------------
; Assuming default 1 MHz SMCLK (1,000,000 ticks per second)
; 10,000 ticks = 0.01 seconds (10ms) per polling loop
TICK_CCR0       .equ    10000           ; Period for one polling tick
HOLD_TICKS      .equ    300             ; 300 ticks * 10ms = 3000ms = 3 seconds
BLINK_TICKS     .equ    25              ; 25 ticks * 10ms = 250ms between toggles (2Hz blink)

; -----------------------------------------------------------------------------
; CPU Register Map (State Tracking)
; -----------------------------------------------------------------------------
; R5  = System State Flag (0 = Idle/Waiting, 1 = Blinking)
; R6  = Hold Counter (Accumulates 10ms ticks while both buttons are held)
; R7  = Blink Counter (Counts down to zero to trigger an LED toggle)

            .text
            .global RESET

; -----------------------------------------------------------------------------
; Main Initialization
; -----------------------------------------------------------------------------
RESET:
            mov.w   #02400h, SP               ; Initialize Stack Pointer
            mov.w   #WDTPW|WDTHOLD, &WDTCTL   ; Stop Watchdog Timer
            bic.w   #LOCKLPM5, &PM5CTL0       ; Unlock GPIO pins

            ; Red LED Setup (P1.0)
            bis.b   #BIT0, &P1DIR             ; Set as output
            bic.b   #BIT0, &P1OUT             ; Start OFF

            ; Green LED Setup (P9.7)
            bis.b   #BIT7, &P9DIR             ; Set as output
            bic.b   #BIT7, &P9OUT             ; Start OFF

            ; Button Setup (P1.1 and P1.2)
            bic.b   #(BIT1|BIT2), &P1DIR      ; Set as inputs
            bis.b   #(BIT1|BIT2), &P1REN      ; Enable internal resistors
            bis.b   #(BIT1|BIT2), &P1OUT      ; Set to Pull-Up mode (Active Low)

            ; Timer_A0 Setup (Configured for Polling, NO Interrupts enabled)
            mov.w   #TASSEL__SMCLK|MC__UP|TACLR, &TA0CTL ; Source: SMCLK, Up Mode, Clear Timer
            mov.w   #TICK_CCR0, &TA0CCR0      ; Load 10ms threshold
            bic.w   #CCIFG, &TA0CCTL0         ; Clear any pending compare flags

            ; Initialize State Registers
            clr.w   R5                        ; Start in IDLE state
            clr.w   R6                        ; Reset the 3-second hold counter
            mov.w   #BLINK_TICKS, R7          ; Preload the blink delay counter

; -----------------------------------------------------------------------------
; Main Polling Loop
; -----------------------------------------------------------------------------
MAIN_LOOP:
            ; 1. Synchronize loop execution to a precise 10ms interval
            call    #WAIT_TICK
            
            ; 2. Check the physical state of the buttons
            call    #BOTH_PRESSED             ; Returns Zero flag (Z=1) if BOTH are held
            jz      BOTH_DOWN_PATH            ; Branch if both buttons are down

; ---- Path A: Not Both Pressed (Idle / Reset Phase) ----
; If either button is released, stop everything immediately.
            clr.w   R6                        ; Reset the 3s hold counter
            clr.w   R5                        ; Set state back to IDLE
            call    #LEDS_OFF                 ; Force both LEDs off
            jmp     MAIN_LOOP                 ; Start next tick

; ---- Path B: Both Buttons Pressed (Hold / Blink Phase) ----
BOTH_DOWN_PATH:
            ; Are we already in the blinking state?
            cmp.w   #1, R5
            jeq     DO_BLINKING               ; If yes, jump straight to blink logic

            ; If not blinking yet, we are in the 3-second "Hold" accumulation phase
            inc.w   R6                        ; Add 10ms to the hold counter
            cmp.w   #HOLD_TICKS, R6
            jl      MAIN_LOOP                 ; If < 3 seconds, keep waiting

            ; Reached 3 seconds of continuous holding! Transition to Blink state.
            mov.w   #1, R5                    ; Set state = BLINKING
            mov.w   #BLINK_TICKS, R7          ; Reset blink timer
            bis.b   #BIT0, &P1OUT             ; Turn Red LED ON
            bis.b   #BIT7, &P9OUT             ; Turn Green LED ON
            jmp     MAIN_LOOP

; ---- Blinking Animation Phase ----
DO_BLINKING:
            dec.w   R7                        ; Tick down the 250ms blink delay
            jnz     MAIN_LOOP                 ; If not zero, don't toggle yet
            
            ; Time to toggle the LEDs
            mov.w   #BLINK_TICKS, R7          ; Reset the blink timer
            call    #TOGGLE_BOTH              ; Flip LED states
            jmp     MAIN_LOOP

; -----------------------------------------------------------------------------
; Subroutines
; -----------------------------------------------------------------------------
; Wastes CPU cycles until the hardware Timer_A0 sets its compare flag.
; This guarantees exactly 10ms passes between loop iterations.
WAIT_TICK:
WT_LOOP:
            bit.w   #CCIFG, &TA0CCTL0         ; Check the hardware Capture/Compare Interrupt Flag
            jz      WT_LOOP                   ; If 0, keep waiting
            bic.w   #CCIFG, &TA0CCTL0         ; Flag triggered! Clear it manually for the next tick
            ret

; Reads Port 1 and determines if BOTH P1.1 and P1.2 are pulled logic LOW.
BOTH_PRESSED:
            mov.b   &P1IN, R4                 ; Copy the entire Port 1 input register
            and.b   #(BIT1|BIT2), R4          ; Mask out everything except the two button bits
            
            ; Because the buttons are Pull-Up, unpressed = 1 and pressed = 0.
            ; If BOTH are pressed, the masked value in R4 will be exactly 0x00.
            cmp.b   #000h, R4                 ; Compare to 0. Sets the Z flag to 1 if true.
            ret

LEDS_OFF:
            bic.b   #BIT0, &P1OUT             ; Force Red OFF
            bic.b   #BIT7, &P9OUT             ; Force Green OFF
            ret

TOGGLE_BOTH:
            xor.b   #BIT0, &P1OUT             ; Flip Red
            xor.b   #BIT7, &P9OUT             ; Flip Green
            ret

; -----------------------------------------------------------------------------
; Interrupt Linker Directives
; -----------------------------------------------------------------------------
; No ISR vectors are defined because this program runs entirely on polling.
            .sect   ".reset"
            .short  RESET