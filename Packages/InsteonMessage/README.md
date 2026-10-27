# InsteonMessage

Build INSTEON messages and encode them for sending to a modem or hub.

- `InsteonAddress`: device addresses, parsed from and printed as `1A.2B.3C`
- `MessageFlags`: the flags byte, with typed message type and hop counts
- `StandardMessage` and `ExtendedMessage`: messages ready for a modem's send command
- `StandardDirectCommand` and `ExtendedDirectCommand`: typed catalogues of common commands
- `UserData`, plus `ChecksumIntegrity` and `CRCIntegrity`: extended-message data with the integrity bytes i2cs devices require

See the DocC catalog in `Sources/InsteonMessage/InsteonMessage.docc` for the full documentation, including the byte-level message format.
