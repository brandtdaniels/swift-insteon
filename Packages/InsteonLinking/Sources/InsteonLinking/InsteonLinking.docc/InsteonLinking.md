# ``InsteonLinking``

Link Insteon devices to each other and to the modem.

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
| Database | ``Linker/link(_:)`` writes both records directly, with exact link data | i2, and i2CS once linked to the modem |
| Remote | ``Linker/linkRemotely(_:modemRole:modemGroup:deviceGroup:timeout:)`` puts the modem and the device into linking mode, as their SET buttons would | i2 and i2CS |
| Manual | ``Linker/linkManually(modemRole:group:timeout:)`` puts the modem into linking mode and waits for someone to press a device's SET button | Every engine |

Remote and manual linking work between the modem and one device, and the device memorizes
its current state as its link data. Database linking works between any two devices, and sets
the link data exactly. ``Unlinker`` has the same three ways, and
``Unlinker/unlinkAllRemotely(_:unlinkingMode:timeout:willUnlink:)`` removes every link
between the modem and a device, in both directions, without its SET button.

A responder memorizes its level as Data 1 of its record, its on-level for the group, so a
device linked while it's off stays off when the controller turns the group on. Call
``Linker/prepareResponder(_:state:)`` before a link in which the device responds; it turns
the device fully on unless given another ``ResponderState``.

``Linker/linkManually(as:group:device:timeout:ready:)`` calls back once the modem is in
linking mode, which is when to tell a person to press the SET button, and can leave the
modem's role to the device. It and
``Unlinker/unlinkManually(as:group:device:timeout:ready:)`` throw ``LinkMismatch`` when
another device links, or the device links where it was to unlink, or the reverse.

To wait for what a device sends after a request, such as the broadcast that answers ID
Request, use ``LinkingModem/firstReply(within:clock:after:matching:)``, which starts
listening before it sends.

A device's engine decides how it's put into linking mode remotely: an i2 device is sent the
standard Enter Linking Mode, and an i2CS device the extended one with a checksum. The linker
asks the device for its engine first; an i2CS device that isn't linked to the modem rejects
that request, which marks it as i2CS. An i1 device can't be linked remotely.

While the modem waits, any device whose SET button is pressed can link to it. So a wait that
fails takes the modem out of linking mode, and the device too after a remote link, and the
linker reports a link with a device other than the one asked for, in another group, or of
another kind, as ``LinkingError/unexpectedLink(_:)``. A canceled link returns once the modem is
out of linking mode, so the next one can start right away.

### Which devices accept database writes

Writing records needs Read/Write ALL-Link Database, which every device with an i2 or i2CS
engine has and i1 devices don't. An i2CS device accepts it only from a device it's already
linked to, so link the modem to an i2CS device with its SET button first.

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

For a device that's gone, such as one thrown away, ``Unlinker/deleteModemRecords(of:)``
deletes every record of the modem's that names it, without sending the device anything. The
device's own records stay, so it's for a device that won't come back.

### Reading databases less often

Reading a device's database takes a request for every record, so a linker reads each
database once per call. To read it less often across calls, give ``Linker`` and ``Unlinker``
the same ``AllLinkDatabaseCache``. It keeps each device's database along with the device's
ALL-Link database delta, a byte the device changes whenever its database does, and before
reusing a copy it asks the device for its delta with one status request. The databases in
the modem and the devices stay the source of truth: a database the linker changes is read
again next time rather than kept as written, and the linker asks the modem itself before
changing the modem's records.

## Topics

### Groups

- ``AllLinkGroup``
- ``LinkEndpoint``
- ``ModemRole``

### Linking

- ``Linker``
- ``Unlinker``
- ``LinkingError``
- ``LinkMismatch``
- ``LinkingDirection``
- ``ManualLinkingRole``
- ``ResponderState``
- ``ModemLink``
- ``UnlinkingModeMessage``

### Databases

- ``AllLinkDatabaseCache``
- ``AllLinkDatabaseCopy``
- ``AllLinkDatabaseReading``
- ``AllLinkGroupReader``
- ``AllLinkGroupReading``

### Identifying devices

- ``DeviceIdentifier``
- ``DeviceIdentification``

### Modems

- ``LinkingModem``
