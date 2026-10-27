# InsteonSerialCommand

Build the serial commands a host sends to an INSTEON modem, such as a PowerLinc Modem or the modem inside an INSTEON Hub.

- `SerialCommand`: every host-to-modem command, `0x60` through `0x77`, encoded to bytes
- `SerialCommandSender`: the protocol modem connections conform to
- `AllLinkRecord`, `AllLinkRecordFlags`, `AllLinkRecordAction` and `AllLinkMode`: ALL-Link database records and linking
- `ModemConfiguration`: the modem's configuration flags
- `X10Code`: X10 unit addresses and commands

See the DocC catalog in `Sources/InsteonSerialCommand/InsteonSerialCommand.docc` for the full documentation.
