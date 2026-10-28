# Supported Modems

The INSTEON modems ``Modem`` works with, and how they differ.

## Overview

``Modem`` speaks the INSTEON modem (IM) serial commands, so it works with every modem that
uses them, whatever the connection:

| Model | Product | Connection | Support |
| --- | --- | --- | --- |
| 2413U, 2413UH | PowerLinc Modem | USB, through ``SerialPort`` | Supported |
| 2413S, 2413SH | PowerLinc Modem | Serial, through ``SerialPort`` | Supported |
| 2412U, 2412UH | PowerLinc Modem | USB, through ``SerialPort`` | Supported; some commands may be rejected, see <doc:SupportedModems#Commands-a-modem-may-lack> |
| 2412S, 2412SH | PowerLinc Modem | Serial, through ``SerialPort`` | Supported; some commands may be rejected, see <doc:SupportedModems#Commands-a-modem-may-lack> |
| 2448A7, 2448A7H | USB Adapter | USB, through ``SerialPort`` | Supported, by radio only; see <doc:SupportedModems#The-USB-Adapter> |
| 2245 | Hub 2 | Network, through `HubConnection` in InsteonHubClient | Supported |
| 2242 | Hub 1 | Network, through `HubConnection` in InsteonHubClient | Expected to work: it serves the same local HTTP requests, though its buffer format hasn't been verified |
| 2414S | PowerLinc Controller | Serial at 4800 baud, through ``SerialPort`` | Supported by ``PowerLincController`` rather than ``Modem``; see <doc:SupportedModems#The-PowerLinc-Controller> |

These aren't supported:

- **PowerLinc Controller by USB (2414U):** it connects through USB HID rather than a serial
  port.
- **SmartLinc (2412N):** its interface isn't documented.
- **Hub Pro (2243):** it's built around HomeKit and has no documented local modem interface.

### Identifying a modem

The reply to `SerialCommand.getModemInfo` carries the modem's device category, subcategory and
firmware version in a `ModemInfo`. Every modem in the table reports category `0x03`, and the
subcategory tells the models apart. To name the model, look the category and subcategory up
in a device database.

### Commands a modem may lack

The INSTEON Developer's Guide defines the IM serial commands `0x60` through `0x73`. The
commands after those, such as Cancel Cleanup (`0x74`), Read and Write Database
(`0x75`, `0x76`), Beep (`0x77`), Set Responder Link Data (`0x79`), Set Application Retries
(`0x7A`) and Set RF Disable Flag (`0x7D`), appear only in Insteon's PLM serial command table,
so a modem whose firmware doesn't implement one, such as a 2412 PowerLinc Modem, may reject it.

The same table lists Set Status (`0x78`), Set RF Frequency (`0x7B`) and Set Venstar ACKs
(`0x7C`) without their parameters, so `SerialCommand` doesn't include them. It also gives two
layouts for the reply to Read RF Frequency (`0x7E`) and two sets of LED colors for Set Salad
Flag (`0x7F`), depending on the product, so those are left out too.

A modem rejects a command it lacks with a NAK, the same answer it gives when it's busy, so
``Modem/send(_:)`` sends the command again as its ``RetryPolicy`` allows before it
throws ``ModemError/rejected(_:)``.

### The USB Adapter

The USB Adapter (2448A7) sends and receives INSTEON messages by radio only. In Insteon's
test log for it, it rejects X10 commands and Beep, so expect ``ModemError/rejected(_:)`` for
`SerialCommand.sendX10(_:)` and `SerialCommand.beep`.

### The PowerLinc Controller

The PowerLinc Controller (2414S) runs IBIOS rather than the IM serial commands: the host sends
an INSTEON message by writing it into the controller's memory and setting a flag.
``PowerLincController`` does that for standard messages and X10, confirming each write with
Get Checksum before it sets the flag, since the controller's ACK means only that it received
the bytes. It also answers
`SerialCommand.getModemInfo` with the controller's version, so code written against
`SerialCommandSender` works with it. It doesn't carry extended messages or the modem's
ALL-Link database commands.

The memory addresses it uses come from the worked examples in the INSTEON Developer's Guide,
which use the controller's i1 INSTEON engine. Messages from devices arrive through the SALad
program the controller ships with.
