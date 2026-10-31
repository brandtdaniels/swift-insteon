# ``InsteonDeviceCatalog``

Find what an Insteon device is and can do from the category, subcategory and firmware version
it reports.

## Overview

Every Insteon device reports a category, a subcategory and a firmware version: when it's asked
to identify itself, when its SET button is pressed, and in some heartbeats. The Insteon device
catalog turns those into a ``DeviceProfile``: the product's model and name, its ALL-Link
groups, and its capabilities, such as dimming, what a sensor means
by each command it sends, and how often it sends a heartbeat.

So a product is supported by adding its profile to the catalog, rather than by writing code
for it. The catalog is a set of static JSON files published on GitHub Pages; this package
ships a copy, so lookups work offline.

The copy is in the package's resource bundle, one of ``DeviceCatalog/bundleNames``, which a
command has to be installed beside. ``DeviceCatalog/bundled()`` looks for the bundle where the
Swift Package Manager and Xcode put it, and throws ``DeviceCatalogError/missingBundledCatalog``
if it isn't there, rather than stopping the process. ``DeviceCatalog/bundled(nextTo:)`` looks in
directories of an app's own, and ``DeviceCatalog/load(contentsOf:)`` reads a catalog from any
file.

```swift
let catalog = try DeviceCatalog.bundled()

guard let profile = catalog.profile(category: 0x10, subcategory: 0x08, firmwareVersion: nil) else {
  return
}

print(profile.model, profile.name)   // "2852 Leak Sensor"

// A broadcast from the sensor to group 2 with cmd1 0x11.
if profile.event(group: 0x02, command1: 0x11) == "wet" {
  print("Water detected")
}

// Not hearing a heartbeat for longer than this means the sensor may have stopped working.
print(profile.heartbeatInterval ?? .zero)
```

``DeviceCatalogUpdater`` keeps an app's copy current: it reads the published manifest, goes on
only if its ``DeviceCatalogVersion`` has the same MAJOR.MINOR as the copy the package ships
with, ``DeviceCatalog/bundledVersion()``, downloads the catalog only when the manifest's
SHA-256 differs from the app's copy, and uses the download only if it hashes to that SHA-256.
Below 1.0 any MINOR can change the catalog's format, so a catalog with another MAJOR.MINOR
waits for an update of the package. A published version older than the app's copy, whose
version the app passes to ``DeviceCatalogUpdater/update(replacing:currentVersion:)``, or than
the bundled copy is refused with ``DeviceCatalogUpdateError/olderThanCurrent(_:)``, so a stale
cache or a rolled-back site never takes back newer data. Updating is optional.

The catalog isn't signed, so a download's integrity rests on HTTPS to the expected host plus
the manifest's SHA-256. The SHA-256 only shows that the catalog matches a manifest fetched
from the same host, so the updater's default client follows a redirect only to HTTPS at
the same host and port, deciding before each one, by
``DeviceCatalogUpdater/redirectPolicy``. A redirect that leaves HTTPS, even for one step on
the way back to HTTPS elsewhere, or goes to another host fails the update, and the app keeps
its copy.

``DeviceEventInterpreter`` reads the messages a modem receives as ``DeviceEvent``s. It learns
each device's profile when the device reports its identity, such as when its SET button is
held to link it, and from then on reports what the device's group commands mean and when it
sends a heartbeat. An app seeds it with the identities it saved, using
``DeviceEventInterpreter/remember(category:subcategory:firmwareVersion:for:)``, so an updated
catalog finds each device's profile again.

``DeviceCatalog/commandSet(category:subcategory:firmwareVersion:)`` finds the ``CommandSet`` a
device uses: its operating flags, read with Get Operating Flags and changed with Set Operating
Flags, the values it reads and writes with extended Get and Set, such as a dimmer's ramp
rate or a keypad's button masks, its other standard and extended direct commands, such as a
thermostat's setpoints, and the direct messages it sends on its own, such as a thermostat's
reports. Many products share a command set, so the catalog describes each once.

A command set's ``CommandSet/settingItems`` are what a settings page shows, each a
``SettingItem`` with its label, ``SettingSection`` and whether it's advanced, in the catalog's
order of sections. ``CommandSet/text(for:raw:)`` shows a value with its value table, unit and
scale, such as "0.5 s" or "50%", and ``CommandSet/raw(for:parsing:)`` reads what someone types
back into the byte to write. ``CommandSet/change(for:setting:)`` and
``CommandSet/change(for:)`` say how to change a flag or value, as a ``FlagChange`` or
``ValueChange``, or that the catalog gives no way.

A command set's group types, each a ``GroupType`` that a profile's groups name, say what the
groups are: how to read a group's state, what it can be told to do, and what Data 1 through
Data 3 of an ALL-Link database record hold for it, each a ``LinkDataByte``. A group type can
also say which bits of a shared status byte mean the group is on, in
``GroupType/State/onWhen``, which outputs of its load one action switches together, in
``GroupType/outputs``, and, for an alarm or arming group, its ``GroupType/armModes``. A
profile's ``DeviceLifecycle`` gives the steps to install, link, wake, reset and remove the
product, for an app to guide people through or do itself, and its
``DeviceLifecycle/fromHub`` gives linking to a Hub as data: the links to make with the
modem, in order, each a ``DeviceLifecycle/HubLinking/Leg``, whether the modem can put the
device in linking mode, and how to keep a battery-powered device awake. A modem's profile
says what the records it writes itself hold, in ``DeviceProfile/modemLinkData``, and an
identity gives the product key the product reports, in ``DeviceIdentity/productKey``.

Some operating flags can cut a device off from the modem or lock it, so the catalog guards
them. An ``OperatingFlag/writeGuard`` of ``FlagGuard/keep`` means a write leaves the bit as
the device reported it, and ``FlagGuard/neverSet`` that a write may clear it but never sets
it; a bit of an extended command's flags parameter carries the same, in
``FieldBit/writeGuard``. A command whose `sendGuard` is ``CommandGuard/never`` is one an app
never sends. A value whose byte is an operating flags byte names its query in
``SettingValue/flagsQuery``, and ``CommandSet/flagsHeld(by:)`` gives the flags that name its
bits. A command set's ``CommandSet/linkingChanges`` are the flags linking may change on its
own, which a linking flow may set back.

Values from a later version of the catalog are read rather than refused: a kind, guard, role,
mode or answer this package doesn't know keeps its name, and a message in a form it doesn't
read is left out.

``DeviceCatalog/profiles(matching:)`` searches the catalog by model, name, alias or identity,
such as for an app's list of supported products.

``DeviceCatalog/describe(category:subcategory:firmwareVersion:)`` gathers what the catalog
says about one device into a ``DeviceDescription``: its profile, command set, name, engine,
main group and the groups it controls. Its ``DeviceDescription/explain(_:isController:)``
reads the data bytes of a record in the device's ALL-Link database as a
``RecordDataExplanation``, such as a responder record's on-level and ramp rate.

A device with no profile can still be handled by what its `DeviceCategory` implies, such as
dimming for dimmable lighting control, as ``GroupType/Kind/fallback(for:)`` gives it.

## Topics

### The catalog

- ``DeviceCatalog``
- ``DeviceCatalogError``

### Describing a device

- ``DeviceDescription``
- ``RecordDataExplanation``

### Updating

- ``DeviceCatalogUpdater``
- ``DeviceCatalogUpdate``
- ``DeviceCatalogUpdateError``
- ``DeviceCatalogVersion``

### Reading events

- ``DeviceEventInterpreter``
- ``DeviceEvent``

### Profiles

- ``DeviceProfile``
- ``DeviceIdentity``
- ``DeviceCapability``
- ``DeviceEngine``
- ``FirmwareSelection``
- ``ProductModel``
- ``DeviceEventName``
- ``DeviceLifecycle``
- ``ModemLinkData``
- ``ModemLinkDataByte``

### Settings

- ``CommandSet``
- ``CommandSetID``
- ``CommandSetEntry``
- ``SettingName``
- ``OperatingFlag``
- ``OperatingReading``
- ``OperatingFlagCommand``
- ``ExtendedSettings``
- ``SettingValue``
- ``SettingWrite``
- ``SettingWriteError``
- ``ValueTable``
- ``SettingItem``
- ``SettingSection``
- ``FlagChange``
- ``ValueChange``
- ``SettingInputError``
- ``FlagGuard``
- ``CommandGuard``
- ``LinkingChange``

### Groups

- ``GroupType``
- ``LinkDataByte``

### Messages

- ``DeviceStandardCommand``
- ``DeviceExtendedCommand``
- ``DeviceExtendedReply``
- ``DeviceDirectMessage``
- ``FixedUserDataByte``
- ``MessageIntegrity``
- ``MessageField``
- ``FieldLocation``
- ``FieldKind``
- ``FieldUnit``
- ``FieldEnumeration``
- ``FieldBit``
- ``FieldValue``
- ``FieldError``

### How sure a value is

- ``Verification``
