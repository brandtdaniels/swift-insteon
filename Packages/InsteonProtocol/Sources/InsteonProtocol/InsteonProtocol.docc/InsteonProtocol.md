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
depend on the protocol rather than on a particular connection. Turn the bytes the modem sends
back, such as command echoes and messages from devices, into typed replies with
``ModemReplyParser``.

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

### Products

- <doc:IdentifyingDevices>
- ``DeviceCategory``
- ``DeviceSubcategory``
- ``FirmwareVersion``
- ``SetButtonPressed``
- ``ProductData``

### Modem commands

- ``SerialCommand``
- ``SerialCommandNumber``
- ``SerialCommandSender``
- ``ModemConfiguration``

### Modem replies

- ``ModemReplyParser``
- ``ModemReply``
- ``ReceivedMessage``
- ``CommandEcho``
- ``ModemInfo``
- ``ModemConfigurationReport``
- ``AllLinkingCompleted``
- ``ModemButtonEvent``

### PowerLinc Controller (IBIOS)

- ``IBIOSCommand``
- ``IBIOSReplyParser``
- ``IBIOSReply``
- ``IBIOSEcho``
- ``IBIOSEvent``

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
