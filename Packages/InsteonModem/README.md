# InsteonModem

Talk to an INSTEON modem, such as a PowerLinc Modem connected by USB (2413U) or serial cable (2413S).

- `Modem`: sends serial commands one at a time, waits for the modem to accept each, retries when it's busy, and streams everything it sends back; conforms to `SerialCommandSender`
- `ModemConnection`: the byte-level connection `Modem` talks over
- `SerialPort`: a `ModemConnection` to a serial or USB modem, on macOS and Linux

See the DocC catalog in `Sources/InsteonModem/InsteonModem.docc` for the full documentation.
