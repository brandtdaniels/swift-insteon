# ``InsteonProtocol``

The Insteon protocol as value types: messages for devices, and the serial commands that carry
them through a modem.

## Overview

Insteon devices talk to each other over the powerline and RF using short messages. A host,
such as your app, reaches them through an Insteon modem, like a PowerLinc Modem or the modem
inside an Insteon Hub, by sending it serial commands. This module models both layers and
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
- ``LightLevel``
- ``AllLinkCommandAlias``

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
- ``ProductKey``
- ``ReportedIdentity``
- ``SetButtonPressed``
- ``ProductData``

### Group commands

- ``GroupCommand``
- ``AllLinkCommand``
- ``GroupCommandFilter``
- ``SuccessReport``

### Broadcasts

- ``Heartbeat``
- ``HeartbeatMonitor``
- ``PowerlinePhaseTest``
- ``RadioRangeTest``
- ``DeviceStatusChanged``

### Parsing replies

- ``ReplyParser``

### Modem commands

- ``SerialCommand``
- ``SerialCommandNumber``
- ``SerialCommandSender``
- ``ModemConfiguration``
- ``RadioSetting``
- ``DeviceRecordRequest``
- ``DeviceRecordOptions``

### Modem replies

- ``ModemReplyParser``
- ``ModemReply``
- ``ReceivedMessage``
- ``CommandEcho``
- ``ModemInfo``
- ``ModemConfigurationReport``
- ``AllLinkingCompleted``
- ``ModemButtonEvent``
- ``ModemDiagnosticRecord``
- ``ModemRadioStatus``

### PowerLinc Controller (IBIOS)

- ``IBIOSCommand``
- ``IBIOSReplyParser``
- ``IBIOSReply``
- ``IBIOSCommandNumber``
- ``IBIOSEcho``
- ``IBIOSEvent``

### ALL-Linking

- ``AllLinkGroupNumber``
- ``AllLinkMode``
- ``AllLinkRecord``
- ``AllLinkRecordFlags``
- ``AllLinkRecordAction``

### Device ALL-Link databases

- ``AllLinkDatabaseRequest``
- ``AllLinkRecordResponse``

### X10

- ``X10Code``
- ``X10HouseCode``
- ``X10UnitCode``
- ``X10Command``

### Encoding

- ``ByteEncodable``
