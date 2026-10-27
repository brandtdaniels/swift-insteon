# Supported Modems

The INSTEON modems ``Modem`` works with, and how they differ.

## Overview

``Modem`` speaks the INSTEON modem (IM) serial commands, so it works with every modem that
uses them, whatever the connection:

| Model | Product | Connection | Support |
| --- | --- | --- | --- |
| 2413U, 2413UH | PowerLinc Modem | USB, through ``SerialPort`` | Supported |
| 2413S, 2413SH | PowerLinc Modem | Serial, through ``SerialPort`` | Supported |
| 2412U, 2412UH | PowerLinc Modem | USB, through ``SerialPort`` | Supported, though some commands may be rejected; see "Commands on older modems" |
| 2412S, 2412SH | PowerLinc Modem | Serial, through ``SerialPort`` | Supported, though some commands may be rejected; see "Commands on older modems" |
| 2448A7, 2448A7H | USB Adapter | USB, through ``SerialPort`` | Supported, by radio only; see "The USB Adapter" |
| 2245, 2242 | Hub | Network, through `HubConnection` in InsteonHubClient | Supported |

These aren't supported:

- **PowerLinc Controller (2414U, 2414S):** it uses the IBIOS serial commands, a different
  protocol from the IM serial commands.
- **SmartLinc (2412N):** its interface isn't documented.
- **Hub Pro (2243):** it's built around HomeKit and has no documented local modem interface.

### Identifying a modem

The reply to `SerialCommand.getModemInfo` carries the modem's device category, subcategory and
firmware version in a `ModemInfo`. Every modem in the table reports category `0x03`, and the
subcategory tells the models apart. To name the model, look the category and subcategory up
in a `ProductDatabase` from InsteonProtocol.

### Commands on older modems

The 2009 INSTEON Developer's Guide lists the IM serial commands `0x60` through `0x73`. The
commands after those, such as Cancel Cleanup (`0x74`), Read and Write Database
(`0x75`, `0x76`), Beep (`0x77`), Set Responder Link Data (`0x79`) and Set Application Retries
(`0x7A`), came with later firmware. A modem whose firmware lacks a command rejects it, and
``Modem/send(_:)`` throws ``ModemError/rejected(_:)``.

### The USB Adapter

The USB Adapter (2448A7) sends and receives INSTEON messages by radio only. In Insteon's
own test log it rejects X10 commands and Beep, so expect ``ModemError/rejected(_:)`` for
`SerialCommand.sendX10(_:)` and `SerialCommand.beep`.
