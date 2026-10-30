# ``InsteonCore``

Keep track of the Insteon devices on a network, for an app or a command to build on.

## Overview

InsteonCore is the library a front end depends on, such as an app or the `insteon` command.
It keeps the devices an app knows and what the Insteon device catalog says about each.

A ``DeviceRegistry`` holds each device's address and the identity it reported: its category,
subcategory and firmware version. It describes every device with the catalog, and describes
them all again when it's given a newer catalog, so no device is lost when the catalog
changes. The registry never sends anything to a modem or a device; record what a device
reports, and look it up later by its address:

```swift
import InsteonCore

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

The file holds only device addresses and identities, never credentials, names or rooms. Its
format has a version, so later versions can add to it, and the store never replaces a file it
can't read, such as one in a newer format.

## Topics

### Devices

- ``DeviceRegistry``
- ``RegisteredDevice``

### Keeping devices

- ``DeviceRegistrySnapshot``
- ``DeviceRegistryStore``
- ``JSONFileDeviceRegistryStore``
- ``DeviceRegistryStoreError``
