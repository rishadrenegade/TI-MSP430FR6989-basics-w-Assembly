;******************************************************************************
; Project: RC522 RFID Passcode System
; Hardware: MSP430FR6989 LaunchPad + MFRC522 RFID Reader
; Description: 
;   - Reads the Unique ID (UID) of presented 13.56MHz RFID tags via SPI.
;   - Compares the scanned UID against a stored "passcode" in memory.
;   - Flashes Green for an authorized tag, Red for an unauthorized tag.
;   - Holding the Left button while scanning a tag overwrites the stored 
;     passcode, effectively programming a new master key.
;
; Wiring:
;       RC522 SCK   -> P3.0 (UCB1CLK)
;       RC522 MOSI  -> P3.1 (UCB1SIMO)
;       RC522 MISO  -> P4.7 (UCB1SOMI)
;       RC522 SDA   -> P1.5 (Chip Select)
;       RC522 RST   -> P1.3 (Hardware Reset)
;       RC522 3.3V  -> 3.3V
;       RC522 GND   -> GND
;******************************************************************************

            .cdecls C,LIST,"msp430.h"
            .def    RESET

            .text
            .retain
            .retainrefs

; -----------------------------------------------------------------------------
; RC522 Internal Register Addresses
; -----------------------------------------------------------------------------
CommandReg      .equ    01h
ComIEnReg       .equ    02h
ComIrqReg       .equ    04h
ErrorReg        .equ    06h
FIFODataReg     .equ    09h             ; 64-byte FIFO buffer for data TX/RX
FIFOLevelReg    .equ    0Ah             ; Number of bytes currently in FIFO
ControlReg      .equ    0Ch
BitFramingReg   .equ    0Dh             ; Adjusts bit-oriented frames
CollReg         .equ    0Eh             ; Collision detection register

ModeReg         .equ    11h             ; Defines general transmitting/receiving modes
TxControlReg    .equ    14h             ; Controls antenna driver pins
TxASKReg        .equ    15h             ; Controls transmit modulation settings
TModeReg        .equ    2Ah             ; Internal timer settings
TPrescalerReg   .equ    2Bh
TReloadRegH     .equ    2Ch             ; Timer reload value (High byte)
TReloadRegL     .equ    2Dh             ; Timer reload value (Low byte)
VersionReg      .equ    37h             ; Returns the RC522 software version

; -----------------------------------------------------------------------------
; RC522 System Commands
; -----------------------------------------------------------------------------
PCD_Idle        .equ    00h             ; Cancel current command
PCD_Transceive  .equ    0Ch             ; Transmit and receive data
PCD_SoftReset   .equ    0Fh             ; Reset the MFRC522

; -----------------------------------------------------------------------------
; PICC (Proximity Integrated Circuit Card) Commands
; -----------------------------------------------------------------------------
PICC_REQIDL     .equ    26h             ; Request idle - find antenna area tags
PICC_ANTICOLL   .equ    93h             ; Anti-collision - read tag UID

; -----------------------------------------------------------------------------
; Internal Status Codes
; -----------------------------------------------------------------------------
MI_OK           .equ    00h             ; Success
MI_ERR          .equ    01h             ; General error
MI_NOTAG        .equ    02h             ; No tag detected in field

; -----------------------------------------------------------------------------
; RAM Variables
; -----------------------------------------------------------------------------
            .bss    version_byte, 1       ; Stores RC522 hardware version
            .bss    status_byte, 1        ; Tracks success/fail of last SPI transaction
            .bss    back_bits, 1          ; Tracks valid received bits
            .bss    temp_buf, 8           ; General purpose buffer
            .bss    tag_table, 5          ; Holds the 5-byte UID of the currently scanned tag
            .bss    tag_len, 1            ; Length of scanned UID
            .bss    passcode_table, 5     ; Holds the 5-byte UID of the authorized master key
            .bss    pass_len, 1           ; Length of master key
            .bss    i_var, 1              ; Loop iterator
            .bss    btn_lock, 1           ; Software debounce/lock for the programming button

; -----------------------------------------------------------------------------
; Main Initialization
; -----------------------------------------------------------------------------
RESET:
            mov.w   #2400H, SP              ; Initialize Stack Pointer
            mov.w   #WDTPW | WDTHOLD, &WDTCTL ; Stop Watchdog Timer

            ; Status LEDs
            bic.b   #BIT0, &P1OUT           ; Red LED (P1.0) OFF
            bis.b   #BIT0, &P1DIR
            bic.b   #BIT7, &P9OUT           ; Green LED (P9.7) OFF
            bis.b   #BIT7, &P9DIR

            ; Left Button (P1.1 - Active Low)
            bic.b   #BIT1, &P1DIR           ; Input
            bis.b   #BIT1, &P1REN           ; Enable resistor
            bis.b   #BIT1, &P1OUT           ; Pull-up

            ; RC522 Control Pins (CS = P1.5, RST = P1.3)
            bis.b   #BIT5 | BIT3, &P1DIR    ; Outputs
            bis.b   #BIT5 | BIT3, &P1OUT    ; Default HIGH (Inactive)

            ; Hardware SPI Pins (eUSCI_B1)
            bic.b   #BIT0 | BIT1, &P3SEL1   ; P3.0 = UCB1CLK, P3.1 = UCB1SIMO
            bis.b   #BIT0 | BIT1, &P3SEL0
            bis.b   #BIT7, &P4SEL1          ; P4.7 = UCB1SOMI
            bic.b   #BIT7, &P4SEL0

            ; eUSCI_B1 SPI Master Configuration
            mov.w   #UCSWRST, &UCB1CTLW0    ; Hold in software reset
            ; Clock Phase High, MSB first, Synchronous Master, SMCLK source
            mov.w   #UCSWRST | UCCKPH | UCMSB | UCSYNC | UCMST | UCSSEL__SMCLK, &UCB1CTLW0
            mov.w   #32, &UCB1BRW           ; SPI Clock Prescaler
            bic.w   #UCSWRST, &UCB1CTLW0    ; Release reset

            bic.w   #LOCKLPM5, &PM5CTL0     ; Unlock GPIO

            ; Load Default Master Key (Hardcoded UID)
            mov.b   #04h, &pass_len
            mov.b   #0B0h, &passcode_table
            mov.b   #0ACh, &passcode_table+1
            mov.b   #07Eh, &passcode_table+2
            mov.b   #07Ah, &passcode_table+3
            mov.b   #00h, &passcode_table+4

            mov.b   #00h, &tag_len
            mov.b   #00h, &btn_lock

            ; Boot the MFRC522 Chip
            call    #rc522_init

            ; Diagnostic: Read RC522 Firmware Version to ensure SPI is working
            mov.b   #VersionReg, R15
            call    #rfid_read
            mov.b   R14, &version_byte

            ; Valid versions are typically 0x91 or 0x92
            cmp.b   #091h, &version_byte
            jeq     MainLoop
            cmp.b   #092h, &version_byte
            jeq     MainLoop

VersionFail:
            ; If SPI fails to read the version, trap the CPU and turn on Red LED
            bis.b   #BIT0, &P1OUT
            bic.b   #BIT7, &P9OUT
            jmp     VersionFail

; -----------------------------------------------------------------------------
; Core Execution Loop
; -----------------------------------------------------------------------------
MainLoop:
            call    #check_left_button      ; Check if user is programming a new master key

            call    #rc522_request_strict   ; Ping antenna to see if a tag is present
            cmp.b   #MI_OK, &status_byte
            jne     MainLoop                ; If no tag, restart loop

            call    #rc522_anticoll         ; Read the UID of the detected tag into tag_table
            cmp.b   #MI_OK, &status_byte
            jne     MainLoop                ; If read failed, restart loop

            call    #check_left_button      ; Check button again post-scan to save tag if needed
            call    #compare_tables         ; Compare tag_table to passcode_table

            cmp.b   #00h, &status_byte
            jeq     GoodTag                 ; Match found

BadTag:
            call    #blink_red              ; No match -> Access Denied
            call    #medium_pause           ; Debounce gap before next scan
            jmp     MainLoop

GoodTag:
            call    #blink_green            ; Match -> Access Granted
            call    #medium_pause
            jmp     MainLoop

; -----------------------------------------------------------------------------
; Master Key Programming Logic
; -----------------------------------------------------------------------------
; Checks if Left Button is held. If YES, copies the most recently scanned 
; UID (tag_table) into the authorized memory block (passcode_table).
check_left_button:
            bit.b   #BIT1, &P1IN            ; Read P1.1 (Active Low)
            jnz     ButtonReleased

            cmp.b   #01h, &btn_lock         ; Ensure we only copy once per press
            jeq     CheckDone

            mov.b   #01h, &btn_lock         ; Set lock

            tst.b   &tag_len                ; Ensure we actually have a tag scanned
            jz      CheckDone

            ; Copy Loop: tag_table -> passcode_table
            mov.b   &tag_len, &pass_len
            mov.b   &tag_len, R12
            mov.w   #tag_table, R4
            mov.w   #passcode_table, R5

CopyLoop:
            tst.b   R12
            jz      CheckDone
            mov.b   @R4+, 0(R5)             ; Move byte and auto-increment source
            inc.w   R5                      ; Increment destination
            dec.b   R12
            jmp     CopyLoop

ButtonReleased:
            mov.b   #00h, &btn_lock         ; Release lock when button is let go

CheckDone:
            ret

; -----------------------------------------------------------------------------
; UID Validation
; -----------------------------------------------------------------------------
; Compares byte-by-byte. Sets status_byte = 00 if exact match, 01 if fail.
compare_tables:
            mov.b   &tag_len, R12
            cmp.b   &pass_len, R12          ; Fast fail if lengths don't match
            jne     CompareFail

            mov.w   #tag_table, R4
            mov.w   #passcode_table, R5

CompareLoop:
            tst.b   R12                     ; Check if all bytes compared
            jz      CompareOK

            mov.b   @R4+, R6                ; Load scanned byte
            cmp.b   @R5+, R6                ; Compare to authorized byte
            jne     CompareFail             ; Fail immediately on first mismatch

            dec.b   R12
            jmp     CompareLoop

CompareOK:
            mov.b   #00h, &status_byte
            ret

CompareFail:
            mov.b   #01h, &status_byte
            ret

; -----------------------------------------------------------------------------
; RC522 Hardware Control
; -----------------------------------------------------------------------------
rc522_init:
            ; Hardware Reset Toggle
            bic.b   #BIT3, &P1OUT
            call    #short_delay
            bis.b   #BIT3, &P1OUT
            call    #short_delay

            ; Software Reset Command
            mov.b   #CommandReg, R15
            mov.b   #PCD_SoftReset, R14
            call    #rfid_write
            call    #long_delay

            ; Timer Settings (Required for proper 13.56MHz modulation timing)
            mov.b   #TModeReg, R15
            mov.b   #8Dh, R14               ; Auto-timer start, prescaler hi
            call    #rfid_write

            mov.b   #TPrescalerReg, R15
            mov.b   #3Eh, R14               ; Prescaler lo
            call    #rfid_write

            mov.b   #TReloadRegL, R15
            mov.b   #1Eh, R14               ; Timer reload val = 30
            call    #rfid_write

            mov.b   #TReloadRegH, R15
            mov.b   #00h, R14
            call    #rfid_write

            mov.b   #TxASKReg, R15          ; 100% ASK Modulation
            mov.b   #40h, R14
            call    #rfid_write

            mov.b   #ModeReg, R15           ; CRC initial value 0x6363
            mov.b   #3Dh, R14
            call    #rfid_write

            call    #antenna_on             ; Energize RF field
            ret

antenna_on:
            mov.b   #TxControlReg, R15
            call    #rfid_read
            mov.b   R14, R12
            and.b   #03h, R12               ; Check if TX1 and TX2 are already on
            cmp.b   #03h, R12
            jeq     AntDone

            mov.b   #TxControlReg, R15
            call    #rfid_read
            mov.b   R14, R12
            bis.b   #03h, R12               ; Turn on TX1 and TX2
            mov.b   #TxControlReg, R15
            mov.b   R12, R14
            call    #rfid_write
            call    #long_delay
AntDone:
            ret

; -----------------------------------------------------------------------------
; RC522 Tag Communication Sequences
; -----------------------------------------------------------------------------
rc522_request_strict:
            mov.b   #MI_NOTAG, &status_byte
            mov.b   #00h, &back_bits

            mov.b   #BitFramingReg, R15     ; 7 valid bits for REQA command
            mov.b   #07h, R14
            call    #rfid_write

            mov.b   #PICC_REQIDL, &temp_buf ; Command PICC to IDLE mode
            call    #rc522_reqa_transceive

            mov.b   #BitFramingReg, R15
            mov.b   #00h, R14
            call    #rfid_write

            cmp.b   #MI_OK, &status_byte
            jne     ReqDone

            cmp.b   #10h, &back_bits        ; 16 bits = valid ATQA response
            jeq     ReqDone

            mov.b   #MI_NOTAG, &status_byte
ReqDone:
            ret

; Transmits data to FIFO and forces the antenna to send it out
rc522_reqa_transceive:
            mov.b   #MI_NOTAG, &status_byte

            mov.b   #ComIEnReg, R15         ; Enable IRQ flags
            mov.b   #0A0h, R14
            call    #rfid_write

            mov.b   #CommandReg, R15        ; Clear current command
            mov.b   #PCD_Idle, R14
            call    #rfid_write

            mov.b   #ComIrqReg, R15         ; Clear interrupt bits
            mov.b   #7Fh, R14
            call    #rfid_write

            mov.b   #FIFOLevelReg, R15      ; Flush FIFO
            mov.b   #80h, R14
            call    #rfid_write

            mov.b   #FIFODataReg, R15       ; Load data to FIFO
            mov.b   #PICC_REQIDL, R14
            call    #rfid_write

            mov.b   #CommandReg, R15        ; Execute Transceive
            mov.b   #PCD_Transceive, R14
            call    #rfid_write

            mov.b   #BitFramingReg, R15     ; Start transmission
            mov.b   #87h, R14
            call    #rfid_write

            mov.w   #4000, R11              ; Timeout counter
WaitIRQ1:
            mov.b   #ComIrqReg, R15
            call    #rfid_read
            mov.b   R14, R10

            bit.b   #20h, R10               ; Check RxIRq
            jnz     GotRx1

            bit.b   #01h, R10               ; Check TimerIRq (Timeout)
            jnz     NoCard1

            dec.w   R11
            jnz     WaitIRQ1
            jmp     NoCard1

GotRx1:
            mov.b   #BitFramingReg, R15     ; Clear start transmit bit
            mov.b   #00h, R14
            call    #rfid_write

            mov.b   #ErrorReg, R15          ; Check for protocol errors
            call    #rfid_read
            mov.b   R14, R10
            bit.b   #1Bh, R10
            jnz     ReqError1

            mov.b   #FIFOLevelReg, R15      ; Read how many bytes responded
            call    #rfid_read
            mov.b   R14, R8

            mov.b   #ControlReg, R15        ; Read bit alignment
            call    #rfid_read
            mov.b   R14, R9
            and.b   #07h, R9

            ; Calculate valid received bits
            mov.b   R8, R7
            rla.b   R7
            rla.b   R7
            rla.b   R7
            mov.b   R7, &back_bits
            tst.b   R9
            jz      ReqSuccess1
            sub.b   #08h, &back_bits
            add.b   R9, &back_bits

ReqSuccess1:
            mov.b   #MI_OK, &status_byte
            ret

NoCard1:
            mov.b   #BitFramingReg, R15
            mov.b   #00h, R14
            call    #rfid_write
            mov.b   #MI_NOTAG, &status_byte
            ret

ReqError1:
            mov.b   #MI_ERR, &status_byte
            ret

; Extracts the full Unique Identifier (UID) from the tag
rc522_anticoll:
            mov.b   #MI_ERR, &status_byte
            mov.b   #00h, &back_bits

            mov.b   #BitFramingReg, R15
            mov.b   #00h, R14
            call    #rfid_write

            mov.b   #CollReg, R15           ; Clear collision flags
            mov.b   #80h, R14
            call    #rfid_write

            mov.b   #ComIEnReg, R15
            mov.b   #0A0h, R14
            call    #rfid_write

            mov.b   #CommandReg, R15
            mov.b   #PCD_Idle, R14
            call    #rfid_write

            mov.b   #ComIrqReg, R15
            mov.b   #7Fh, R14
            call    #rfid_write

            mov.b   #FIFOLevelReg, R15      ; Flush FIFO
            mov.b   #80h, R14
            call    #rfid_write

            mov.b   #FIFODataReg, R15       ; Send Anti-collision command
            mov.b   #PICC_ANTICOLL, R14
            call    #rfid_write

            mov.b   #FIFODataReg, R15       ; NVB (Number of Valid Bits)
            mov.b   #20h, R14
            call    #rfid_write

            mov.b   #CommandReg, R15        ; Execute Transceive
            mov.b   #PCD_Transceive, R14
            call    #rfid_write

            mov.b   #BitFramingReg, R15     ; Start transmit
            mov.b   #80h, R14
            call    #rfid_write

            mov.w   #4000, R11
WaitIRQ2:
            mov.b   #ComIrqReg, R15
            call    #rfid_read
            mov.b   R14, R10

            bit.b   #20h, R10               ; Check RxIRq
            jnz     GotRx2

            bit.b   #01h, R10               ; Check TimerIRq (Timeout)
            jnz     AntiFail

            dec.w   R11
            jnz     WaitIRQ2
            jmp     AntiFail

GotRx2:
            mov.b   #BitFramingReg, R15     ; Stop transmitting
            mov.b   #00h, R14
            call    #rfid_write

            mov.b   #ErrorReg, R15          ; Check for errors
            call    #rfid_read
            mov.b   R14, R10
            bit.b   #1Bh, R10
            jnz     AntiFail

            mov.b   #FIFOLevelReg, R15      ; Ensure we got exactly 5 bytes back
            call    #rfid_read
            mov.b   R14, R8
            cmp.b   #05h, R8
            jne     AntiFail

            mov.w   #tag_table, R6          ; Point to RAM table
            mov.b   #05h, &i_var            ; 5 bytes to read

ReadUIDLoop:
            mov.b   #FIFODataReg, R15
            call    #rfid_read              ; Read byte from RC522 FIFO
            mov.b   R14, 0(R6)              ; Store in tag_table
            inc.w   R6
            dec.b   &i_var
            jnz     ReadUIDLoop

            mov.b   #05h, &tag_len

            ; Block Check Character (BCC) Verification
            ; The 5th byte is an XOR sum of the first 4 bytes.
            mov.b   &tag_table, R12
            xor.b   &tag_table+1, R12
            xor.b   &tag_table+2, R12
            xor.b   &tag_table+3, R12
            cmp.b   &tag_table+4, R12       ; Verify calculation against received BCC
            jne     AntiFail

            mov.b   #MI_OK, &status_byte
            ret

AntiFail:
            mov.b   #BitFramingReg, R15
            mov.b   #00h, R14
            call    #rfid_write
            mov.b   #MI_ERR, &status_byte
            ret

; -----------------------------------------------------------------------------
; Direct SPI Hardware Interface
; -----------------------------------------------------------------------------
; Writes data (R14) to RC522 register (R15)
rfid_write:
            mov.b   R14, R13

            bic.b   #BIT5, &P1OUT           ; Pull CS LOW
            rla.b   R15                     ; Shift register address left (Bit 0 must be 0 for write)
            and.b   #7Eh, R15               ; Mask address format 
            call    #spi_send               ; Send address
            mov.b   R13, R15
            call    #spi_send               ; Send data
            bis.b   #BIT5, &P1OUT           ; Pull CS HIGH
            ret

; Reads data from RC522 register (R15) into R14
rfid_read:
            bic.b   #BIT5, &P1OUT           ; Pull CS LOW
            rla.b   R15                     ; Shift register address left
            and.b   #7Eh, R15               ; Mask address format
            bis.b   #80h, R15               ; Bit 7 must be 1 for read
            call    #spi_send               ; Send read address
            mov.b   #00h, R15               ; Send dummy byte to clock in the data
            call    #spi_send
            bis.b   #BIT5, &P1OUT           ; Pull CS HIGH
            ret

; Primitive to push a byte to the hardware buffer and wait for response
spi_send:
WaitTX:
            bit.w   #UCTXIFG, &UCB1IFG      ; Wait until transmit buffer is ready
            jz      WaitTX
            mov.b   R15, &UCB1TXBUF         ; Push byte

WaitRX:
            bit.w   #UCRXIFG, &UCB1IFG      ; Wait until receive buffer has captured the response
            jz      WaitRX
            mov.b   &UCB1RXBUF, R14         ; Store received byte
            ret

; -----------------------------------------------------------------------------
; LED / Feedback Subroutines
; -----------------------------------------------------------------------------
blink_green:
            bis.b   #BIT7, &P9OUT
            call    #short_delay
            bic.b   #BIT7, &P9OUT
            ret

blink_red:
            bis.b   #BIT0, &P1OUT
            call    #short_delay
            bic.b   #BIT0, &P1OUT
            ret

; -----------------------------------------------------------------------------
; Software Delays
; -----------------------------------------------------------------------------
short_delay:
            mov.w   #12000, R15
SD1:        dec.w   R15
            jnz     SD1
            ret

medium_pause:
            mov.w   #50000, R15
MP1:        dec.w   R15
            jnz     MP1
            ret

long_delay:
            mov.w   #45000, R15
LD1:        dec.w   R15
            jnz     LD1
            ret

; -----------------------------------------------------------------------------
; Interrupt Vectors
; -----------------------------------------------------------------------------
            .sect   ".reset"
            .short  RESET
            .end