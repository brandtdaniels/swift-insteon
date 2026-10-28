# InsteonModem

Talk to an Insteon modem, such as a PowerLinc Modem 2413U connected by USB or a 2413S connected by serial cable.

## Supported modems

| Model | Product | Connection | Support |
| --- | --- | --- | --- |
| 2413U, 2413UH, 2413S, 2413SH | PowerLinc Modem | USB or serial, through `SerialPort` | Supported |
| 2412U, 2412UH, 2412S, 2412SH | PowerLinc Modem | USB or serial, through `SerialPort` | Supported; commands after `0x73` may be rejected |
| 2448A7, 2448A7H | USB Adapter | USB, through `SerialPort` | Supported, by radio only; expect X10 and Beep to be rejected |
| 2245 | Hub | Network, through `HubConnection` in InsteonHubClient | Supported |
| 2242 | Hub | Network, through `HubConnection` in InsteonHubClient | Expected to work; its buffer format hasn't been verified |
| 2243 | Hub Pro | Network, through `HubConnection` in InsteonHubClient | Expected to work: it's built on the same foundations as the other Hubs, though it hasn't been verified |
| 2414S | PowerLinc Controller | Serial at 4800 baud, through `SerialPort` | Supported by `PowerLincController`, which speaks IBIOS: standard messages, X10 and version |
| 2414U | PowerLinc Controller | USB HID | Not supported: it connects through USB HID, not a serial port |
| 2412N | SmartLinc | Network | Not supported: its interface isn't documented |

The Supported Modems article in the documentation explains each caveat.

## Types

- `Modem`: sends serial commands one at a time, waits for the modem to accept each, retries when it's busy, and streams everything it sends back; sends messages to devices and waits for each device to acknowledge them, or for the reply that follows; reads a device's ALL-Link database; conforms to `SerialCommandSender`
- `ModemConnection`: the byte-level connection `Modem` talks over
- `PowerLincController`: sends standard messages and X10 through a PowerLinc Controller 2414S using IBIOS, and streams what it reports; conforms to `SerialCommandSender`
- `SerialPort`: a `ModemConnection` to a serial or USB modem, on macOS and Linux, at 19200 or 4800 baud
- `ModemDiscovery`: finds modems on the computer's USB-to-serial adapters, or on serial devices the user picks, by asking each for its modem information, on macOS and Linux

See the DocC catalog in `Sources/InsteonModem/InsteonModem.docc` for the full documentation.
