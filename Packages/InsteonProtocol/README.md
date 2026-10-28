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

`Sources/InsteonProtocol/Products` covers how devices identify themselves:

- `DeviceCategory`, `DeviceSubcategory` and `FirmwareVersion`: a device's category (DevCat), subcategory (SubCat) and firmware version, with the developer guide's named categories, such as `.dimmableLightingControl`
- `SetButtonPressed` and `ProductData`: read the identity a device reports in reply to an ID request or a product data request

No device data is built in, so every app can look devices up in one shared device database instead of keeping its own list.

## Modem

`Sources/InsteonProtocol/Modem` covers the serial commands a host sends to an INSTEON modem, such as a PowerLinc Modem or the modem inside an INSTEON Hub:

- `SerialCommand`: the host-to-modem commands `0x60` through `0x77`, `0x79`, `0x7A` and `0x7D`, encoded to bytes
- `SerialCommandSender`: the protocol modem connections conform to
- `AllLinkGroup`, `AllLinkRecord`, `AllLinkRecordFlags`, `AllLinkRecordAction` and `AllLinkMode`: ALL-Link groups, database records and linking
- `ModemConfiguration`: the modem's configuration flags
- `X10Code`: X10 unit addresses and commands
- `ModemReplyParser` and `ModemReply`, through the `ReplyParser` protocol: turn the bytes a modem sends back into typed replies: command echoes with ACK/NAK, lone NAKs, messages received from devices, ALL-Link records and more

## PowerLinc Controller

`Sources/InsteonProtocol/IBIOS` covers IBIOS, the serial protocol of the PowerLinc Controller (2414U, 2414S), which gives the host access to the device's memory instead of modem commands:

- `IBIOSCommand` and `IBIOSCommandNumber`: download, upload, checksum, mask, simulated event and get version, encoded to bytes with their checksums
- `IBIOSReplyParser` and `IBIOSReply`: turn the bytes the controller sends into typed replies: echoes with ACK/NAK, memory, event reports, and the INSTEON messages and X10 its SALad program reports
- `IBIOSEvent`: the events IBIOS reports

See the DocC catalog in `Sources/InsteonProtocol/InsteonProtocol.docc` for the full documentation, including the byte-level message format.
