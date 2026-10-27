# InsteonModem

Talk to an INSTEON modem, such as a PowerLinc Modem connected by USB (2413U) or serial cable (2413S).

## Supported modems

| Model | Product | Connection | Support |
| --- | --- | --- | --- |
| 2413U, 2413UH, 2413S, 2413SH | PowerLinc Modem | USB or serial, through `SerialPort` | Supported |
| 2412U, 2412UH, 2412S, 2412SH | PowerLinc Modem | USB or serial, through `SerialPort` | Supported; commands after `0x73` may be rejected |
| 2448A7, 2448A7H | USB Adapter | USB, through `SerialPort` | Supported, by radio only; expect X10 and Beep to be rejected |
| 2245 | Hub 2 | Network, through `HubConnection` in InsteonHubClient | Supported |
| 2242 | Hub 1 | Network, through `HubConnection` in InsteonHubClient | Expected to work; its buffer format hasn't been verified |
| 2414U, 2414S | PowerLinc Controller | USB or serial | Not supported: it uses IBIOS commands, not the IM serial commands |
| 2412N | SmartLinc | Network | Not supported: its interface isn't documented |
| 2243 | Hub Pro | Network | Not supported: it's built around HomeKit and has no documented local modem interface |

The Supported Modems article in the documentation explains each caveat.

## Types

- `Modem`: sends serial commands one at a time, waits for the modem to accept each, retries when it's busy, and streams everything it sends back; conforms to `SerialCommandSender`
- `ModemConnection`: the byte-level connection `Modem` talks over
- `SerialPort`: a `ModemConnection` to a serial or USB modem, on macOS and Linux

See the DocC catalog in `Sources/InsteonModem/InsteonModem.docc` for the full documentation.
