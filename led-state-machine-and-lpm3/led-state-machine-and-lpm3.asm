;******************************************************************************
; Project: LED State Machine & Low-Power Mode 3 (LPM3)
; Hardware: MSP430FR6989 LaunchPad
; Description: 
;   - Red LED blinks continuously.
;   - Holding the Left button stops the Red blink and counts up internally.
;   - Pressing the Right button blinks the Green LED the number of times 
;     the Left button was pressed.
;   - If no buttons are pressed for 5 seconds, the system enters LPM3 
;     (Deep Sleep) where both LEDs blink alternately to indicate sleep mode.
;   - Pressing any button instantly wakes the CPU and resumes normal operation.
;******************************************************************************

            .cdecls C,LIST,"msp430.h"
            .def    RESET
STACK_TOP   .equ    0x2400
            
; -----------------------------------------------------------------------------
; Hardware Pin Definitions
; -----------------------------------------------------------------------------
RED         .equ    BIT0            ; P1.0 (LaunchPad Red LED)
GREEN       .equ    BIT7            ; P9.7 (LaunchPad Green LED)
LB          .equ    BIT1            ; P1.1 (LaunchPad Left Button)
RB          .equ    BIT2            ; P1.2 (LaunchPad Right Button)

; -----------------------------------------------------------------------------
; State Machine Flags (Stored in R15 for high-speed access)
; -----------------------------------------------------------------------------
LEFT_HELD   .equ    0001b           ; Bit 0: Is the left button currently held down?
GREEN_BLK   .equ    0010b           ; Bit 1: Is the green LED currently in a blink sequence?
IN_LPM3     .equ    0100b           ; Bit 2: Is the system currently in Low-Power Mode 3?
GPHASE      .equ    1000b           ; Bit 3: Tracks the ON/OFF phase of the Green LED blink

; -----------------------------------------------------------------------------
; CPU Register Map
; -----------------------------------------------------------------------------
; R12 = greenRemaining  (Counts down the remaining green blinks)
; R13 = inactivityTicks (Counts 0.5s ticks to track the 5-second timeout)
; R14 = leftCount       (Accumulates how many times the left button was pressed)
; R15 = flags           (Holds the bitwise boolean flags defined above)

            .text
            .retain
            .retainrefs

; -----------------------------------------------------------------------------
; Main Initialization
; -----------------------------------------------------------------------------
RESET:
            mov.w   #STACK_TOP, SP          ; Initialize Stack Pointer
            mov.w   #WDTPW|WDTHOLD, &WDTCTL ; Stop Watchdog Timer
            bic.w   #LOCKLPM5, &PM5CTL0     ; Unlock GPIO pins

            ; Configure Red LED (P1.0)
            bic.b   #RED, &P1OUT            ; Start OFF
            bis.b   #RED, &P1DIR            ; Set as Output

            ; Configure Green LED (P9.7)
            bic.b   #GREEN, &P9OUT          ; Start OFF
            bis.b   #GREEN, &P9DIR          ; Set as Output

            ; Configure Buttons (P1.1 and P1.2)
            bic.b   #(LB|RB), &P1DIR        ; Set as Inputs
            bis.b   #(LB|RB), &P1REN        ; Enable internal resistors
            bis.b   #(LB|RB), &P1OUT        ; Set to Pull-Up mode

            ; Configure Button Interrupts
            bis.b   #(LB|RB), &P1IES        ; Trigger on falling edge (button press)
            bic.b   #(LB|RB), &P1IFG        ; Clear interrupt flags before enabling
            bis.b   #(LB|RB), &P1IE         ; Enable interrupts for both buttons

            ; Initialize Variable Registers to Zero
            mov.w   #0, R12
            mov.w   #0, R13
            mov.w   #0, R14
            mov.w   #0, R15

            ; Configure Timer_A1 for a 0.5-second tick
            ; ACLK = 32768 Hz. 32768 / 2 = 16384 ticks for 0.5s.
            mov.w   #CCIE, &TA1CCTL0        ; Enable Timer interrupt
            mov.w   #16384-1, &TA1CCR0      ; Set period to 16383 (zero-indexed)
            mov.w   #TASSEL__ACLK|MC__UP|TACLR, &TA1CTL ; ACLK, Up Mode, Clear timer

            ; Main CPU Sleep State
            nop
            bis.w   #GIE, SR                ; Enable Global Interrupts
            nop
SLEEP:
            bis.w   #LPM0, SR               ; CPU sleeps in LPM0; awakened only by interrupts
            nop
            jmp     SLEEP                   ; Loop back to sleep if woken accidentally

; -----------------------------------------------------------------------------
; Port 1 Interrupt Service Routine (Handles Left and Right Buttons)
; -----------------------------------------------------------------------------
PORT1_ISR:
            mov.w   #0, R13                 ; Any button activity resets the 5s inactivity timer

            ; ---- LEFT BUTTON LOGIC ----
            bit.b   #LB, &P1IFG             ; Check if Left Button triggered the interrupt
            jz      CHECK_RIGHT             ; If not, skip to Right Button

            xor.b   #LB, &P1IES             ; Toggle Edge Select (Listen for release next time)

            bit.b   #LB, &P1IN              ; Read the physical pin state
            jnz     LEFT_RELEASE            ; If HIGH, it was a release. If LOW, it was a press.

LEFT_PRESS:
            ; Wake from LPM3 if the system was asleep
            bit.w   #IN_LPM3, R15
            jz      LP_OK
            bic.w   #IN_LPM3, R15           ; Clear Sleep Flag
            bic.w   #LPM3, 0(SP)            ; Manipulate Stack to wake CPU upon RETI
LP_OK:
            bis.w   #LEFT_HELD, R15         ; Set Left Held Flag
            bic.b   #RED, &P1OUT            ; Force Red LED OFF while held

            ; Do not count if Green LED is currently executing a sequence
            bit.w   #GREEN_BLK, R15
            jnz     CLR_L

            inc.w   R14                     ; leftCount++

CLR_L:
            bic.b   #LB, &P1IFG             ; Clear Left Button interrupt flag
            jmp     DONE_P1

LEFT_RELEASE:
            bic.w   #LEFT_HELD, R15         ; Clear Left Held Flag
            bic.b   #LB, &P1IFG             ; Clear Left Button interrupt flag
            jmp     DONE_P1

            ; ---- RIGHT BUTTON LOGIC ----
CHECK_RIGHT:
            bit.b   #RB, &P1IFG             ; Check if Right Button triggered the interrupt
            jz      DONE_P1

            xor.b   #RB, &P1IES             ; Toggle Edge Select (Listen for release next time)

            bit.b   #RB, &P1IN              ; Read the physical pin state
            jnz     CLR_R                   ; If HIGH (Released), ignore and clear flag

RIGHT_PRESS:
            ; Wake from LPM3 if the system was asleep
            bit.w   #IN_LPM3, R15
            jz      RP_OK
            bic.w   #IN_LPM3, R15           ; Clear Sleep Flag
            bic.w   #LPM3, 0(SP)            ; Manipulate Stack to wake CPU upon RETI
RP_OK:
            ; Ignore press if Green LED is already executing a sequence
            bit.w   #GREEN_BLK, R15
            jnz     CLR_R

            mov.w   R14, R12                ; Copy leftCount to greenRemaining
            tst.w   R12                     ; Check if greenRemaining is 0
            jz      CLR_R                   ; If 0, do nothing

            bis.w   #GREEN_BLK, R15         ; Set Green Blinking Flag
            bic.w   #GPHASE, R15            ; Reset phase to ensure clean start
            bic.b   #GREEN, &P9OUT          ; Ensure Green LED starts OFF

CLR_R:
            bic.b   #RB, &P1IFG             ; Clear Right Button interrupt flag

DONE_P1:
            reti

; -----------------------------------------------------------------------------
; Timer A1 Interrupt Service Routine (Fires every 0.5 Seconds)
; -----------------------------------------------------------------------------
TIMER1_A0_ISR:

            ; ---- LPM3 Deep Sleep Behavior ----
            bit.w   #IN_LPM3, R15           ; Check if system is asleep
            jz      NOT_LPM3
            
            ; If in LPM3, toggle BOTH LEDs every 0.5s to indicate sleep mode
            xor.b   #RED, &P1OUT
            xor.b   #GREEN, &P9OUT
            reti                            ; Exit immediately

NOT_LPM3:
            ; ---- Green LED Sequence Behavior ----
            bit.w   #GREEN_BLK, R15         ; Check if green sequence is active
            jz      NORMAL

            mov.w   #0, R13                 ; Prevent system from sleeping while animating
            xor.b   #GREEN, &P9OUT          ; Toggle Green LED

            ; Decrement remaining blinks only when the LED turns ON (completes a full cycle)
            xor.w   #GPHASE, R15            ; Flip phase flag
            bit.w   #GPHASE, R15            
            jz      TMR_DONE                ; If turning OFF, skip decrement

            dec.w   R12                     ; greenRemaining--
            jnz     TMR_DONE                ; If not 0, sequence continues

            ; Sequence finished
            bic.w   #GREEN_BLK, R15         ; Clear sequence flag
            mov.w   #0, R14                 ; Reset leftCount back to 0
            jmp     TMR_DONE

NORMAL:
            ; ---- Default Red LED Behavior ----
            bic.b   #GREEN, &P9OUT          ; Ensure Green is OFF during normal mode
            
            bit.w   #LEFT_HELD, R15         ; Is the Left button held down?
            jz      TOG_RED                 ; If NO, toggle Red LED normally
            bic.b   #RED, &P1OUT            ; If YES, force Red LED OFF
            jmp     INACT

TOG_RED:
            xor.b   #RED, &P1OUT            ; Normal Red blink heartbeat

INACT:
            ; ---- Inactivity Timer (LPM3 Entry) ----
            inc.w   R13                     ; inactivityTicks++
            cmp.w   #10, R13                ; 10 ticks * 0.5s = 5 seconds
            jne     TMR_DONE                ; If < 5s, exit normally

            ; 5 Seconds of Inactivity Reached -> Enter LPM3
            mov.w   #0, R13                 ; Reset inactivity timer
            bis.w   #IN_LPM3, R15           ; Set Sleep Flag
            bic.b   #RED, &P1OUT            ; Turn off Red LED
            bic.b   #GREEN, &P9OUT          ; Turn off Green LED
            
            bis.w   #LPM3, 0(SP)            ; Manipulate Stack to push CPU into LPM3 upon RETI

TMR_DONE:
            reti

; -----------------------------------------------------------------------------
; Interrupt Linker Directives
; -----------------------------------------------------------------------------
            .sect   ".reset"
            .short  RESET

            .sect   ".int37"                ; PORT1 Vector Map
            .short  PORT1_ISR

            .sect   ".int39"                ; TIMER1_A0 Vector Map
            .short  TIMER1_A0_ISR

            .end