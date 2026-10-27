# InsteonProtocol

The INSTEON protocol as Swift value types, encoded to the bytes INSTEON modems and hubs accept.

## Messages

`Sources/InsteonProtocol/Messages` covers the messages devices exchange:

- `InsteonAddress`: device addresses, parsed from and printed as `1A.2B.3C`
- `MessageFlags`: the flags byte, with typed message type and hop counts
- `StandardMessage` and `ExtendedMessage`: messages ready for a modem's send command
- `Command` and `CommandConvertible`: the two command bytes, and the protocol device commands conform to
- `UserData`, plus `ChecksumIntegrity` and `CRCIntegrity`: extended-message data with the integrity bytes i2cs devices require

The message format is fixed by the protocol, so this layer changes rarely.

## Device commands

`Sources/InsteonProtocol/DeviceCommands` is the catalog of commands devices understand, and the part expected to grow as device types are added:

- `StandardDirectCommand` and `ExtendedDirectCommand`: common commands for any device

New commands conform to `CommandConvertible`, so adding them never touches the message layer.

See the DocC catalog in `Sources/InsteonProtocol/InsteonProtocol.docc` for the full documentation, including the byte-level message format.
