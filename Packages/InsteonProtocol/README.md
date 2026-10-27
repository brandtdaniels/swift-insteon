# InsteonProtocol

The INSTEON protocol as Swift value types, encoded to the bytes INSTEON modems and hubs accept.

## Messages

`Sources/InsteonProtocol/Messages` covers the messages devices exchange:

- `InsteonAddress`: device addresses, parsed from and printed as `1A.2B.3C`
- `MessageFlags`: the flags byte, with typed message type and hop counts
- `StandardMessage` and `ExtendedMessage`: messages ready for a modem's send command
- `Command` and `CommandConvertible`: the two command bytes, and the protocol device commands conform to
- `UserData`, plus `ChecksumIntegrity` and `CRCIntegrity`: extended-message data with the integrity bytes i2cs devices require

The message format is fixed by the protocol.

## Device commands

`Sources/InsteonProtocol/DeviceCommands` is the catalog of commands devices understand, open to additional device types:

- `StandardDirectCommand` and `ExtendedDirectCommand`: common commands for any device

Additional commands conform to `CommandConvertible`, so they never touch the message layer.

## Products

`Sources/InsteonProtocol/Products` covers how devices identify themselves and how an app finds out what they can do:

- `DeviceCategory`: a device's category (DevCat)
- `SetButtonPressed` and `ProductData`: read the identity a device reports in reply to an ID request or a product data request
- `ProductDatabase` and `DeviceCapabilities`: look up what a device can do for its firmware version in a product database, from whichever source the app provides

No device data is built in, so every app reads the same product database instead of keeping its own list.

## Modem

`Sources/InsteonProtocol/Modem` covers the serial commands a host sends to an INSTEON modem, such as a PowerLinc Modem or the modem inside an INSTEON Hub:

- `SerialCommand`: every host-to-modem command, `0x60` through `0x77`, `0x79` and `0x7A`, encoded to bytes
- `SerialCommandSender`: the protocol modem connections conform to
- `AllLinkRecord`, `AllLinkRecordFlags`, `AllLinkRecordAction` and `AllLinkMode`: ALL-Link database records and linking
- `ModemConfiguration`: the modem's configuration flags
- `X10Code`: X10 unit addresses and commands
- `ModemReplyParser` and `ModemReply`: turn the bytes a modem sends back into typed replies: command echoes with ACK/NAK, lone NAKs, messages received from devices, ALL-Link records and more

See the DocC catalog in `Sources/InsteonProtocol/InsteonProtocol.docc` for the full documentation, including the byte-level message format.
