# MSP430FR6989 Assembly Portfolio

A collection of embedded systems projects written entirely in bare-metal Assembly for the TI MSP430FR6989 microcontroller. These projects demonstrate peripheral configuration, hardware interfacing, state machines, and low-power modes without the use of high-level C libraries.

## Hardware & Factory Guides
This repository interfaces with the following hardware. Official documentation and datasheets are linked below for reference:
* **[MSP-EXP430FR6989 LaunchPad](https://www.ti.com/tool/MSP-EXP430FR6989)**: Development board featuring the MSP430FR6989 microcontroller with 128KB FRAM and an onboard segment LCD.
* **[BOOSTXL-EDUMKII BoosterPack](https://www.ti.com/tool/BOOSTXL-EDUMKII)**: Educational BoosterPack featuring a TFT LCD, analog joystick, RGB LED, and push buttons.
* **[MFRC522 RFID Reader (NXP)](https://www.nxp.com/docs/en/data-sheet/MFRC522.pdf)**: 13.56MHz contactless reader used for SPI communication projects.

## Projects Overview
1. **[TFT Crosshair Shooter](./tft-shooter-game/)**: An interactive gallery game utilizing the EDUMKII BoosterPack. The user controls a crosshair with the analog joystick, aiming at spawned targets on the TFT display and firing with hardware buttons. Features score tracking, hit/miss RGB LED feedback, and win-state detection.
2. **[UART to LCD Terminal](./uart-lcd-terminal/)**: A serial communication bridge that displays typed characters from a PC terminal onto the LaunchPad's 14-segment LCD.
3. **[LCD Scrolling Message](./lcd-scrolling-message/)**: A multiplexed 14-segment LCD project that scrolls text, allowing the user to change the scroll direction via hardware interrupts.
4. **[LED State Machine & LPM3](./led-state-machine/)**: A low-power application demonstrating complex state management, timer interrupts, and Low-Power Mode 3 (LPM3) utilization.
5. **[Hold-to-Blink Controller](./hold-to-blink-controller/)**: A timer-polling project requiring simultaneous, sustained button presses to activate a continuous LED sequence.
6. **[Dual Button Toggle](./dual-button-toggle/)**: An interrupt-free state controller using shift-register debouncing to independently toggle two LEDs.
7. **[Basic Blink Sequence](./basic-blink-sequence/)**: A foundational sequence utilizing software delay loops to orchestrate an alternating blink pattern.

## Development Environment
* **IDE**: Code Composer Studio (CCS) v20.4
* **Language**: MSP430 Assembly
