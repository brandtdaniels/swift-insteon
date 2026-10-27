# InsteonModem

Talk to an INSTEON modem, such as a PowerLinc Modem connected by USB (2413U) or serial cable (2413S).

## Supported modems

| Model | Product | Connection | Support |
| --- | --- | --- | --- |
| 2413U, 2413UH, 2413S, 2413SH | PowerLinc Modem | USB or serial, through `SerialPort` | Supported |
| 2412U, 2412UH, 2412S, 2412SH | PowerLinc Modem | USB or serial, through `SerialPort` | Supported; commands after `0x73` may be rejected |
| 2448A7, 2448A7H | USB Adapter | USB, through `SerialPort` | Supported, by radio only; X10 and Beep are rejected |
| 2245, 2242 | Hub | Network, through `HubConnection` in InsteonHubClient | Supported |
| 2414S | PowerLinc Controller | Serial at 4800 baud, through `SerialPort` | Supported by `PowerLincController`, which speaks IBIOS: standard messages, X10 and version |
| 2414U | PowerLinc Controller | USB HID | Not supported: it connects through USB HID, not a serial port |
| 2412N | SmartLinc | Network | Not supported: its interface isn't documented |
| 2243 | Hub Pro | Network | Not supported |

## Types

- `Modem`: sends serial commands one at a time, waits for the modem to accept each, retries when it's busy, and streams everything it sends back; conforms to `SerialCommandSender`
- `ModemConnection`: the byte-level connection `Modem` talks over
- `PowerLincController`: sends standard messages and X10 through a PowerLinc Controller (2414S) using IBIOS, and streams what it reports; conforms to `SerialCommandSender`
- `SerialPort`: a `ModemConnection` to a serial or USB modem, on macOS and Linux, at 19200 or 4800 baud

See the DocC catalog in `Sources/InsteonModem/InsteonModem.docc` for the full documentation.
