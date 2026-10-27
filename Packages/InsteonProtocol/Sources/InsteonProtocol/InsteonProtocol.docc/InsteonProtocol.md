# ``InsteonProtocol``

Build INSTEON messages and encode them for sending to a modem or hub.

## Overview

INSTEON devices talk to each other over the power line and RF using short messages. This
module models those messages as value types and encodes them to the bytes an INSTEON modem
accepts for transmission.

```swift
import InsteonProtocol

let lamp = InsteonAddress("1A.2B.3C")!

let turnOn = StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))
turnOn.hexString  // "1A2B3C0F11FF"
```

Every type is `Sendable` and has no dependencies beyond the Swift standard library.

## Topics

### Messages

- <doc:MessageFormat>
- ``StandardMessage``
- ``ExtendedMessage``
- ``Message``

### Addresses and flags

- ``InsteonAddress``
- ``MessageFlags``

### Commands

- ``Command``
- ``CommandConvertible``
- ``StandardCommandConvertible``

### Device commands

- ``StandardDirectCommand``
- ``ExtendedDirectCommand``
- ``ManualChangeDirection``
- ``OperatingFlagsRequest``
- ``SetButtonTapCount``

### Extended user data

- ``UserData``
- ``UserDataError``
- ``UserDataIntegrity``
- ``ChecksumIntegrity``
- ``CRCIntegrity``
- ``UnprotectedIntegrity``

### Encoding

- ``ByteEncodable``
