# ``InsteonCore``

Keep track of the Insteon devices on a network, for an app or a command to build on.

## Overview

InsteonCore is the library a front end depends on, such as an app or the `insteon` command.
It keeps the devices an app knows and what the Insteon device catalog says about each.

The API uses some types from the lower-level modules, such as `DeviceCatalog` from
InsteonDeviceCatalog, `InsteonAddress` and `ReportedIdentity` from InsteonProtocol, and
`LinkingModem` and `AllLinkDatabaseCopy` from InsteonLinking, so an app imports those modules
too.

A ``DeviceRegistry`` holds each device's address and the identity it reported: its category,
subcategory and firmware version. It describes every device with the catalog, and describes
them all again when it's given a newer catalog, so no device is lost when the catalog
changes. The registry never sends anything to a modem or a device; record what a device
reports, and look it up later by its address:

```swift
import InsteonCore
import InsteonDeviceCatalog

let registry = DeviceRegistry(catalog: try DeviceCatalog.bundled())

await registry.record(identity, for: lamp)

if let known = await registry.device(lamp) {
  print(known.deviceDescription.displayName ?? "unknown product")
}
```

### Keeping devices between launches

A ``DeviceRegistryStore`` keeps a registry's ``DeviceRegistrySnapshot`` between launches.
``JSONFileDeviceRegistryStore`` keeps it in a JSON file that only the current user can read,
replacing the file whole on every save, and reads the `insteon` command's identity cache, so
devices it learned are kept:

```swift
let store = JSONFileDeviceRegistryStore(fileURL: url)
let registry = DeviceRegistry(catalog: catalog, snapshot: try store.load())

await registry.record(identity, for: lamp)
try store.save(await registry.snapshot)
```

The file never holds credentials, the Hub's MAC address, names or rooms. Its format has a
version, so later versions can add to it, and each device's entry has the same keys as an
entry in the `insteon` command's identity cache, so a reader of that cache reads the file too.
The store never replaces a file it can't read, such as one in a newer format.

### Reaching devices through a modem

A ``DeviceNetwork`` owns a modem, a registry and the one cache of ALL-Link databases that
reads through the modem. It lists the modem's ALL-Link database with each device described,
hands back a device's ALL-Link database from its copy while the device reports the same
delta, and identifies devices, sharing an identification already in progress for the same
address. Its ``NetworkSnapshot`` adds to the registry's identities each device's engine, a
copy of its ALL-Link database with the delta it was read at, its last known level and when it
last answered, the modem's ALL-Link database, and the Hub's host, port and Insteon ID:

```swift
let store = JSONFileDeviceRegistryStore(fileURL: url)
let network = DeviceNetwork(modem: modem, catalog: catalog, snapshot: try store.loadNetwork())

let database = try await network.allLinkDatabase(of: lamp)
try store.saveNetwork(await network.snapshot())
```

## Topics

### Devices

- ``DeviceRegistry``
- ``RegisteredDevice``

### Networks

- ``DeviceNetwork``
- ``ModemDatabaseEntry``
- ``NetworkDeviceState``
- ``HubLocation``

### Keeping devices

- ``DeviceRegistrySnapshot``
- ``DeviceRegistryStore``
- ``NetworkSnapshot``
- ``NetworkSnapshotStore``
- ``JSONFileDeviceRegistryStore``
- ``DeviceRegistryStoreError``
