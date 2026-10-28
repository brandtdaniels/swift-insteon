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

### Three ways to link

| Way | How | Engines |
| --- | --- | --- |
| Database | ``Linker/link(_:)`` writes both records directly, with exact link data | i2, and i2cs once linked to the modem |
| Remote | ``Linker/linkRemotely(_:modemRole:modemGroup:deviceGroup:timeout:)`` puts the modem and the device into linking mode, as their SET buttons would | i2 and i2cs |
| Manual | ``Linker/linkManually(modemRole:group:timeout:)`` puts the modem into linking mode and waits for someone to press a device's SET button | Every engine |

Remote and manual linking work between the modem and one device, and the device memorizes
its current state as its link data. Database linking works between any two devices, and sets
the link data exactly. ``Unlinker`` has the same three ways.

A device's engine decides how it's put into linking mode remotely: an i2 device is sent the
standard Enter Linking Mode, and an i2cs device the extended one with a checksum. The linker
asks the device for its engine first; an i2cs device that isn't linked to the modem rejects
that request, which marks it as i2cs. An i1 device can't be linked remotely.

While the modem waits, any device whose SET button is pressed can link to it. So a wait that
fails takes the modem out of linking mode, and the device too after a remote link, and the
linker reports a link with a device other than the one asked for, or of another kind, as
``LinkingError/unexpectedLink(_:)``.

### Which devices accept database writes

Writing records needs Read/Write ALL-Link Database, which every device with an i2 or i2cs
engine has and i1 devices don't. An i2cs device accepts it only from a device it's already
linked to, so link the modem to an i2cs device with its SET button first.

### How records are written

A device's database is a list of 8-byte records whose addresses count down by 8, from
`0x0FFF` to `0x0307`. ``Linker`` writes each responder's record first, then the controller's:

- A responder record updates every record that already links the same devices in the same
  group, otherwise reuses the first record that's no longer in use, otherwise goes at the end
  of the database, after the record below it is marked as the new end.
- A controller record is added only when there's none, since an existing one holds data the
  controller keeps for itself, such as a keypad's button number.

Every write is read back, and each device's database is read once per call, then kept up to
date as records are written. ``Unlinker`` deletes a record by clearing its in-use bit.

The modem's own database is changed with its Manage ALL-Link Record command. Its delete
matches a record's group and address but not its role, so ``Unlinker`` finds every matching
record first, deletes them all, and adds back the ones it's keeping.

## Topics

### Groups

- ``AllLinkGroup``
- ``LinkEndpoint``
- ``ModemRole``

### Linking

- ``Linker``
- ``Unlinker``
- ``LinkingError``

### Modems

- ``LinkingModem``
