# Supported Modems

The Insteon modems ``Modem`` works with, and how they differ.

## Overview

``Modem`` speaks the Insteon modem (IM) serial commands, so it works with every modem that
uses them, whatever the connection:

| Model | Product | Connection | Support |
| --- | --- | --- | --- |
| 2413U, 2413UH | PowerLinc Modem | USB, through ``SerialPort`` | Supported |
| 2413S, 2413SH | PowerLinc Modem | Serial, through ``SerialPort`` | Supported |
| 2412U, 2412UH | PowerLinc Modem | USB, through ``SerialPort`` | Supported; some commands may be rejected, see <doc:SupportedModems#Commands-a-modem-may-lack> |
| 2412S, 2412SH | PowerLinc Modem | Serial, through ``SerialPort`` | Supported; some commands may be rejected, see <doc:SupportedModems#Commands-a-modem-may-lack> |
| 2448A7, 2448A7H | USB Adapter | USB, through ``SerialPort`` | Supported, by radio only; see <doc:SupportedModems#The-USB-Adapter> |
| 2245 | Hub | Network, through `HubConnection` in InsteonHubClient | Supported |
| 2242 | Hub | Network, through `HubConnection` in InsteonHubClient | Expected to work: it serves the same local HTTP requests, though its buffer format hasn't been verified |
| 2243 | Hub Pro | Network, through `HubConnection` in InsteonHubClient | Expected to work: it's built on the same foundations as the other Hubs and answers Hub discovery, though it hasn't been verified |
| 2414S | PowerLinc Controller | Serial at 4800 baud, through ``SerialPort`` | Supported by ``PowerLincController`` rather than ``Modem``; see <doc:SupportedModems#The-PowerLinc-Controller> |

These aren't supported:

- **PowerLinc Controller 2414U:** it connects through USB HID rather than a serial
  port.
- **Central Controller 2412N (SmartLinc):** its interface isn't documented.

### Identifying a modem

The reply to `SerialCommand.getModemInfo` carries the modem's device category, subcategory and
firmware version in a `ModemInfo`. Every modem in the table reports category `0x03`, and the
subcategory tells the models apart. HouseLinc's device catalog lists these:

| Model | Subcategories |
| --- | --- |
| 2413U, 2413UH | `0x15`, `0x1A` |
| 2413S, 2413SH | `0x11`, `0x19` |
| 2412U, 2412UH | `0x0B`, `0x13` |
| 2412S, 2412SH | `0x05`, `0x14` |
| 2448A7 | `0x1F`, `0x20` |
| 2448A7H | `0x21`, `0x23` |
| 2245 | `0x33` to `0x36`, one for each region |
| 2242 | `0x2B`, `0x2E` to `0x32`, one or more for each region |
| 2414S | `0x01` |
| 2412N | `0x10` |
| 2243 | `0x18`, `0x2C`, `0x2D` |

The catalog also lists a Hub as `0x37` without a model number. For any other modem, look the
category and subcategory up in the [Insteon device catalog](https://github.com/brandtdaniels/insteon-device-catalog), which InsteonDeviceCatalog reads.

### Commands a modem may lack

The Insteon Developer's Guide defines the IM serial commands `0x60` through `0x73`. The
commands after those, such as Cancel Cleanup (`0x74`), Read and Write Database
(`0x75`, `0x76`), Beep (`0x77`), Set Responder Link Data (`0x79`), Set Application Retries
(`0x7A`) and Set RF Disable Flag (`0x7D`), aren't in the Insteon Developer's Guide,
so a modem whose firmware doesn't implement one, such as a PowerLinc Modem 2412, may reject it.
The Insteon Hub Developer's Guide marks `0x79` through `0x7C` as commands for modems with
a radio only, so a powerline-only modem may reject those too.

Read RF Frequency (`0x7E`), Diagnostics (`0x81`) and Database Commands (`0x82`) come from
later firmware. For Read RF Frequency, `SerialCommand` reads the modem's
layout of the reply, not the development dongle's.

Set Status (`0x78`), Set RF Frequency (`0x7B`) and Set Venstar ACKs (`0x7C`) have no known
parameters, so `SerialCommand` doesn't include them. Set Salad Flag (`0x7F`) sets different LED
colors on different products, and `0x80` has two meanings, so those are left out too.

A modem rejects a command it lacks with a NAK, the same answer it gives when it's busy, so
``Modem/send(_:)`` sends the command again as its ``RetryPolicy`` allows before it
throws ``ModemError/rejected(_:)``.

### The USB Adapter

The USB Adapter 2448A7 sends and receives Insteon messages by radio only. It rejects X10
commands and Beep, so expect ``ModemError/rejected(_:)`` for
`SerialCommand.sendX10(_:)` and `SerialCommand.beep`.

### The PowerLinc Controller

The PowerLinc Controller 2414S runs IBIOS rather than the IM serial commands: the host sends
an Insteon message by writing it into the controller's memory and setting a flag.
``PowerLincController`` does that for standard messages and X10, confirming each write with
Get Checksum before it sets the flag, since the controller's ACK means only that it received
the bytes. It also answers
`SerialCommand.getModemInfo` with the controller's version, so code written against
`SerialCommandSender` works with it. It doesn't carry extended messages or the modem's
ALL-Link database commands.

The memory addresses it uses come from the worked examples in the Insteon Developer's Guide,
which use the controller's i1 Insteon engine. Messages from devices arrive through the SALad
program the controller ships with.
