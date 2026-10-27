# ``InsteonProtocol``

The INSTEON protocol as value types: messages for devices, and the serial commands that carry
them through a modem.

## Overview

INSTEON devices talk to each other over the power line and RF using short messages. A host,
such as your app, reaches them through an INSTEON modem, like a PowerLinc Modem or the modem
inside an INSTEON Hub, by sending it serial commands. This module models both layers and
encodes them to bytes:

```swift
import InsteonProtocol

let lamp = InsteonAddress("1A.2B.3C")!
let turnOn = StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))

turnOn.hexString                                    // "1A2B3C0F11FF"
SerialCommand.sendStandardMessage(turnOn).hexString  // "02621A2B3C0F11FF"
```

Connections to a modem conform to ``SerialCommandSender``, so code that sends commands can
depend on the protocol rather than on a particular connection.

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
- ``NAKReason``
- ``InsteonEngine``

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

### Modem commands

- ``SerialCommand``
- ``SerialCommandNumber``
- ``SerialCommandSender``
- ``ModemConfiguration``

### ALL-Linking

- ``AllLinkMode``
- ``AllLinkRecord``
- ``AllLinkRecordFlags``
- ``AllLinkRecordAction``

### X10

- ``X10Code``
- ``X10HouseCode``
- ``X10UnitCode``
- ``X10Command``

### Encoding

- ``ByteEncodable``
