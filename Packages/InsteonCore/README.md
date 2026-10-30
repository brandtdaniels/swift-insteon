# InsteonCore

Keep track of the Insteon devices on a network: the library an app or a command builds on.

## Types

- `DeviceRegistry`: the devices an app knows, each with the identity it reported and what the Insteon device catalog says about it; it never sends anything to a modem or a device, and describes every device again when given a newer catalog
- `RegisteredDevice`: a device's address, identity and catalog description
- `DeviceRegistrySnapshot`: a registry's devices as a value to save and restore
- `DeviceRegistryStore`: somewhere an app keeps a registry's devices between launches
- `JSONFileDeviceRegistryStore`: keeps them in a versioned JSON file only the current user can read, replaced whole on every save; it also reads the `insteon` command's identity cache, and never replaces a file it can't read
- `DeviceRegistryStoreError`: why the file couldn't be read or written

The store holds only device addresses and identities, never credentials, names or rooms.

See the DocC catalog in `Sources/InsteonCore/InsteonCore.docc` for the full documentation.
