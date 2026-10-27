# ``InsteonSerialCommand``

Build the serial commands a host sends to an INSTEON modem.

## Overview

INSTEON modems, such as the PowerLinc Modem and the modem inside an INSTEON Hub, are
controlled with serial commands. Each command starts with `0x02` and a command number,
followed by its parameters. This package models every host-to-modem command as a case of
``SerialCommand`` and encodes it to bytes.

```swift
import InsteonMessage
import InsteonSerialCommand

let lamp = InsteonAddress(0xAA, 0xBB, 0xCC)
let turnOn = StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))

SerialCommand.sendStandardMessage(turnOn).hexString  // "0262AABBCC0F11FF"
SerialCommand.startAllLinking(mode: .controller, group: 0x01).hexString  // "02640101"
```

Connections to a modem conform to ``SerialCommandSender``, so code that sends commands can
depend on the protocol rather than on a particular connection.

## Topics

### Commands

- ``SerialCommand``
- ``SerialCommandNumber``
- ``SerialCommandSender``

### ALL-Linking

- ``AllLinkMode``
- ``AllLinkRecord``
- ``AllLinkRecordFlags``
- ``AllLinkRecordAction``

### Modem configuration

- ``ModemConfiguration``

### X10

- ``X10Code``
- ``X10HouseCode``
- ``X10UnitCode``
- ``X10Command``
