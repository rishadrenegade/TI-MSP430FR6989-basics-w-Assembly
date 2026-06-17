;******************************************************************************
; Project: Dual Button Toggle (Interrupt-Free State Controller)
; Hardware: MSP430FR6989 LaunchPad
; Description: 
;   - Left Button: Toggles Red LED blinking ON/OFF and forces Green OFF.
;   - Right Button: Toggles Green LED blinking ON/OFF and forces Red OFF.
;   - Uses Shift-Register debouncing for zero-latency, accurate press detection.
;   - Operates entirely via continuous polling; NO Interrupt Service Routines.
;******************************************************************************

            .cdecls C,LIST,"msp430.h"

; -----------------------------------------------------------------------------
; State Flags & Constants
; -----------------------------------------------------------------------------
; Bit flags mapped to register R6 to track which system is currently active
RED_EN      .equ    0001h       ; R6 bit 0: 1 = Red blinking enabled
GRN_EN      .equ    0002h       ; R6 bit 1: 1 = Green blinking enabled

; Defines the speed of the LED blink. Because this program runs in a continuous 
; loop without delays, this number must be large to create a visible blink.
BLINK_RELOAD .equ   10000

            .text
            .global RESET

; -----------------------------------------------------------------------------
; Main Initialization
; -----------------------------------------------------------------------------
RESET:
            mov.w   #02400h, SP             ; Initialize stack pointer
            mov.w   #WDTPW|WDTHOLD, &WDTCTL ; Stop watchdog timer
            bic.w   #LOCKLPM5, &PM5CTL0     ; Unlock GPIO pins

            ; Red LED Setup (P1.0)
            bis.b   #BIT0, &P1DIR           ; Set as output
            bic.b   #BIT0, &P1OUT           ; Start OFF

            ; Green LED Setup (P9.7)
            bis.b   #BIT7, &P9DIR           ; Set as output
            bic.b   #BIT7, &P9OUT           ; Start OFF

            ; Button Setup (P1.1 and P1.2)
            bic.b   #(BIT1|BIT2), &P1DIR    ; Set as inputs
            bis.b   #(BIT1|BIT2), &P1REN    ; Enable internal resistors
            bis.b   #(BIT1|BIT2), &P1OUT    ; Set to Pull-Up mode (Active Low)

; -----------------------------------------------------------------------------
; CPU Register Map
; -----------------------------------------------------------------------------
; R6  = Master enable flags (RED_EN, GRN_EN)
; R10 = Left button shift register (History of P1.1 states)
; R11 = Right button shift register (History of P1.2 states)
; R12 = Red LED blink countdown timer
; R13 = Green LED blink countdown timer

            ; Initialize Registers
            clr.w   R6                      ; Both LEDs disabled at boot
            mov.w   #0FFFFh, R10            ; Pre-fill Left history with 1s (Unpressed)
            mov.w   #0FFFFh, R11            ; Pre-fill Right history with 1s (Unpressed)
            mov.w   #BLINK_RELOAD, R12      ; Load Red timer
            mov.w   #BLINK_RELOAD, R13      ; Load Green timer

; -----------------------------------------------------------------------------
; Main Polling & Logic Loop
; -----------------------------------------------------------------------------
MAIN_LOOP:

; ---- LEFT BUTTON DEBOUNCE & LOGIC ----
            rla.w   R10                     ; Shift Left history register left by 1
            bit.b   #BIT1, &P1IN            ; Read physical P1.1 pin state
            jnz     L_RELEASED              ; If HIGH (1), button is released

; Button is Pressed (LOW)
            bic.w   #0001h, R10             ; Insert a 0 into the LSB of history
            jmp     L_CHECK

L_RELEASED:
            bis.w   #0001h, R10             ; Insert a 1 into the LSB of history

L_CHECK:
            ; Check for the exact moment of a valid press:
            ; 0x8000 in binary is 1000 0000 0000 0000.
            ; This means the last 15 checks were "Released" (1), and the very 
            ; newest check is "Pressed" (0). This filters out bouncing.
            cmp.w   #08000h, R10
            jne     RIGHT_BTN               ; If not an exact press, move on

; Left Press Validated: Toggle Red, Force Green OFF
            xor.w   #RED_EN, R6             ; Toggle the Red Enable flag
            bic.w   #GRN_EN, R6             ; Force Green Enable flag OFF
            bic.b   #BIT7, &P9OUT           ; Turn Green LED OFF physically
            mov.w   #BLINK_RELOAD, R13      ; Reset Green blink timer

            ; Determine whether Red should turn ON or stay OFF based on new toggle state
            bit.w   #RED_EN, R6
            jz      L_RED_OFF
            bis.b   #BIT0, &P1OUT           ; State is Enabled -> Turn Red ON