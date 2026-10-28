# ``InsteonLinking``

Link INSTEON devices to each other and to the modem.

## Overview

An ALL-Link joins a controller to a responder: when the controller's button is pressed, the
responder recalls the state it keeps for that button's ALL-Link group. Each link is two
records, one in the ALL-Link database of each device: a controller record in the controller,
and a responder record, holding the responder's link data, in the responder.

An ``AllLinkGroup`` describes a controller's group and its responders. ``Linker`` makes the
group's links by writing their records into the devices' databases and the modem's, and
``Unlinker`` removes them:

```swift
import InsteonLinking
import InsteonModem

try await Modem.withConnection(SerialPort(path: "/dev/ttyUSB0")) { modem in
  let group = AllLinkGroup(
    controller: .modem,
    number: 0x05,
    responders: [.init(.device(lamp), data1: 0xFF, data2: 0x1F, data3: 0x01)]
  )

  try await Linker(modem: modem).link(group)
}
```

### Which devices accept database writes

Writing records needs Read/Write ALL-Link Database, which every device with an i2 or i2cs
engine has and i1 devices don't. An i2cs device accepts it only from a device it's already
linked to, so link the modem to an i2cs device with its SET button first.

### How records are written

A device's database is a list of 8-byte records whose addresses count down by 8. ``Linker``
updates a record that already links the same devices in the same group and role, otherwise
reuses the first record that's no longer in use, otherwise adds the record at the end of the
database and marks the record after it as the new end. It reads every record back after
writing it. The modem's own database is written with its Manage ALL-Link Record command.

## Topics

### Groups

- ``AllLinkGroup``
- ``LinkEndpoint``

### Linking

- ``Linker``
- ``Unlinker``
- ``LinkingError``

### Modems

- ``LinkingModem``
