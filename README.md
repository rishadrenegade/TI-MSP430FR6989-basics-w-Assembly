# MSP430FR6989 Assembly Portfolio

A collection of embedded systems projects written entirely in bare-metal Assembly for the Texas Instruments MSP430FR6989 microcontroller. These projects demonstrate a progressive mastery of microcontroller architecture, peripheral configuration, hardware interfacing, and low-power management without the use of high-level C libraries.

## Hardware & Factory Guides
This repository interfaces with the following hardware. Official documentation and datasheets are linked below for reference:

* **[MSP-EXP430FR6989 LaunchPad](https://www.ti.com/tool/MSP-EXP430FR6989)** <br>
  <img src="https://www.ti.com/content/dam/ticom/images/products/ic/microcontrollers/msp/evm-board/msp-exp430fr6989-top.png" width="250">  <br>
  *Development board featuring the MSP430FR6989 microcontroller with 128KB FRAM and an onboard segment LCD.*

* **[BOOSTXL-EDUMKII BoosterPack](https://www.ti.com/tool/BOOSTXL-EDUMKII)** <br>
  <img src="https://www.ti.com/content/dam/ticom/images/products/ic/microcontrollers/msp/evm-board/boostxl-edumkii-bottom.png" width="250">  <br>
  *Educational BoosterPack featuring a TFT LCD, analog joystick, RGB LED, and push buttons.*

* **[MFRC522 RFID Reader (NXP)](https://www.nxp.com/docs/en/data-sheet/MFRC522.pdf)** <br>
  <img src="https://joy-it.net/files/files/Produkte/SBC-RFID-RC522/SBC-RFID-RC522%20(2).png" width="250">  <br>
  *13.56MHz contactless reader used for SPI communication projects.*
## Projects Overview (Basic to Advanced)

**1. [Basic Blink Sequence](./basic-blink-sequence/)**
* **Concepts:** GPIO configuration, software delay loops, sequential flow control.
* **Description:** A foundational sequence utilizing blocking software delay loops to orchestrate an alternating blink pattern between two LEDs.

**2. [Hold-to-Blink Controller](./hold-to-blink-controller/)**
* **Concepts:** Hardware timer polling, active-low logic masking, state tracking.
* **Description:** A timer-polling project requiring simultaneous, sustained button presses for exactly 3 seconds to activate a continuous LED sequence, built entirely without interrupts.

**3. [Dual Button Toggle](./dual-button-toggle/)**
* **Concepts:** Shift-register debouncing, continuous polling state machines.
* **Description:** An interrupt-free state controller using real-time shift-register logic to filter physical button bounce, allowing for zero-latency independent toggling of two LEDs.

**4. [LED State Machine & LPM3](./led-state-machine/)**
* **Concepts:** Interrupt Service Routines (ISRs), Low-Power Mode 3 (LPM3), stack pointer manipulation.
* **Description:** A low-power application demonstrating complex state management. Features an inactivity timeout that pushes the CPU into deep sleep (LPM3), waking instantly via hardware interrupts by manipulating the stack pointer (`0(SP)`) during the ISR return.

**5. [LCD Scrolling Message](./lcd-scrolling-message/)**
* **Concepts:** Multiplexed display control, array pointer math, modulo logic.
* **Description:** A digital marquee that scrolls a custom string across the LaunchPad's 6-character 14-segment LCD. Updates are driven by a Timer interrupt, while hardware button interrupts dynamically reverse the scroll direction.

**6. [UART to LCD Terminal](./uart-lcd-terminal/)**
* **Concepts:** eUSCI_A UART, baud rate generation, ASCII translation, string buffer management.
* **Description:** A serial communication bridge that establishes a 9600-baud connection with a PC terminal. Characters typed on the PC are echoed back and dynamically mapped to hardware hex codes to display on the LaunchPad's LCD, complete with backspace and scrolling support.

**7. [RC522 RFID Passcode System](./rfid-passcode-system/)**
* **Concepts:** eUSCI_B SPI (Master), raw register addressing, data block comparisons.
* **Description:** A hardware access system that communicates with an RC522 module over SPI. It reads the Unique Identifier (UID) of presented tags, compares them against an authorized memory block, and features a button-driven programming mode to overwrite the master passcode.

**8. [TFT Crosshair Shooter Game](./tft-shooter-game/)**
* **Concepts:** Multi-peripheral orchestration, ADC12, Timer PWM, SPI TFT rendering, collision detection.
* **Description:** An interactive gallery game utilizing the EDUMKII BoosterPack. The user controls a crosshair via the analog joystick (ADC), aiming at spawned targets on the TFT display (SPI) and firing with hardware buttons. Features score tracking, hit/miss RGB LED feedback (PWM), and win-state detection.

## Development Environment
* **IDE**: Code Composer Studio (CCS) v20.4
* **Language**: MSP430 Assembly
