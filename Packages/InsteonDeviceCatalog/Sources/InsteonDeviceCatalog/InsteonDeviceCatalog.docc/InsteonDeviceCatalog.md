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

``DeviceCatalogUpdater`` keeps an app's copy current: it downloads the published catalog
only when the published manifest's SHA-256 differs from the app's copy, and uses the download
only if it hashes to that SHA-256. Updating is optional.

``DeviceEventInterpreter`` reads the messages a modem receives as ``DeviceEvent``s. It learns
each device's profile when the device reports its identity, such as when its SET button is
held to link it, and from then on reports what the device's group commands mean and when it
sends a heartbeat.

``DeviceCatalog/commandSet(category:subcategory:firmwareVersion:)`` finds the ``CommandSet`` a
device uses: its operating flags, read with Get Operating Flags and changed with Set Operating
Flags, the values it reads and writes with extended Get and Set, such as a dimmer's ramp
rate or a keypad's button masks, its other standard and extended direct commands, such as a
thermostat's setpoints, and the direct messages it sends on its own, such as a thermostat's
reports. Many products share a command set, so the catalog describes each once.

``DeviceCatalog/profiles(matching:)`` searches the catalog by model, name, alias or identity,
such as for an app's list of supported products.

A device with no profile can still be handled by what its `DeviceCategory` implies, such as
dimming for dimmable lighting control.

## Topics

### The catalog

- ``DeviceCatalog``
- ``DeviceCatalogError``

### Updating

- ``DeviceCatalogUpdater``
- ``DeviceCatalogUpdate``
- ``DeviceCatalogUpdateError``

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
