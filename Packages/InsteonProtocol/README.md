# InsteonProtocol

The Insteon protocol as Swift value types, encoded to the bytes Insteon modems and hubs accept.

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

No device data is built in, so every app can look devices up in the [Insteon device catalog](https://github.com/brandtdaniels/insteon-device-catalog), which InsteonDeviceCatalog reads, instead of keeping its own list.

## Group commands

`Sources/InsteonProtocol/GroupCommands` covers the commands controllers send to their ALL-Link groups, such as a keypad button or a sensor reporting motion. What a product means by each command comes from the device catalog, which InsteonDeviceCatalog's `DeviceEventInterpreter` reads:

- `GroupCommand`: reads a command from an ALL-Link broadcast or cleanup
- `GroupCommandFilter`: passes each command on once, dropping the cleanups that repeat a broadcast and repeated broadcasts
- `SuccessReport`: reads the broadcast a controller sends after its cleanups, with the group's member count and failed cleanups

## Device ALL-Link databases

`Sources/InsteonProtocol/DeviceDatabase` covers the records a device keeps in its own ALL-Link database:

- `AllLinkDatabaseRequest`: reads one record, every record, or writes a record, as the user data of a Read/Write ALL-Link Database message
- `AllLinkRecordResponse`: reads a record a device sends back, with its address

## Modem

`Sources/InsteonProtocol/Modem` covers the serial commands a host sends to an Insteon modem, such as a PowerLinc Modem or the modem inside an Insteon Hub:

- `SerialCommand`: the host-to-modem commands `0x60` through `0x77`, `0x79`, `0x7A` and `0x7D`, encoded to bytes
- `SerialCommandSender`: the protocol modem connections conform to
- `AllLinkGroupNumber`, `AllLinkRecord`, `AllLinkRecordFlags`, `AllLinkRecordAction` and `AllLinkMode`: ALL-Link group numbers, database records and linking
- `ModemConfiguration`: the modem's configuration flags
- `X10Code`: X10 unit addresses and commands
- `ModemReplyParser` and `ModemReply`, through the `ReplyParser` protocol: turn the bytes a modem sends back into typed replies: command echoes with ACK/NAK, lone NAKs, messages received from devices, ALL-Link records and more

## PowerLinc Controller

`Sources/InsteonProtocol/IBIOS` covers IBIOS, the serial protocol of the PowerLinc Controller (2414U, 2414S), which gives the host access to the device's memory instead of modem commands:

- `IBIOSCommand` and `IBIOSCommandNumber`: download, upload, checksum, mask, simulated event and get version, encoded to bytes with their checksums
- `IBIOSReplyParser` and `IBIOSReply`: turn the bytes the controller sends into typed replies: echoes with ACK/NAK, memory, event reports, and the Insteon messages and X10 its SALad program reports
- `IBIOSEvent`: the events IBIOS reports

See the DocC catalog in `Sources/InsteonProtocol/InsteonProtocol.docc` for the full documentation, including the byte-level message format.
