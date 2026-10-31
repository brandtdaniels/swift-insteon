# InsteonCore

Keep track of the Insteon devices on a network: the library an app or a command builds on.

## Types

- `DeviceRegistry`: the devices an app knows, each with the identity it reported and what the Insteon device catalog says about it; it never sends anything to a modem or a device, and describes every device again when given a newer catalog
- `RegisteredDevice`: a device's address, identity and catalog description
- `DeviceRegistrySnapshot`: a registry's devices as a value to save and restore
- `DeviceRegistryStore`: somewhere an app keeps a registry's devices between launches
- `JSONFileDeviceRegistryStore`: keeps them in a versioned JSON file only the current user can read, replaced whole on every save; it also reads the `insteon` command's identity cache, and never replaces a file it can't read
- `DeviceRegistryStoreError`: why the file couldn't be read or written
- `DeviceNetwork`: the devices reached through one modem; lists the modem's ALL-Link database with each device described, hands back a device's ALL-Link database from its copy while the device's delta is the same, and identifies devices, sharing an identification in progress for the same address
- `ModemDatabaseEntry`: a record of the modem's ALL-Link database and the device it names
- `NetworkSnapshot`: what a network knows, to save and restore: the registry's identities, each device's engine, ALL-Link database copy and delta, last known level and when it last answered, the modem's ALL-Link database, and the Hub's location
- `NetworkDeviceState`: what a network learned about one device besides its identity
- `HubLocation`: the Hub's host, port and Insteon ID
- `NetworkSnapshotStore`: somewhere an app keeps a network's snapshot; `JSONFileDeviceRegistryStore` is one
- `Device`: one device on a network, controlled as the Insteon device catalog describes it; reads its settings and changes them, never writing the flags that turn off its radio or powerline or require a checksum, and only turning its programming lock off
- `DeviceSetting`, `DeviceSettingsReading`, `DeviceSettingChange`: a setting with what a settings page shows for it, the settings a device reported, and what a write changed
- `DeviceSettingError`, `DeviceSettingInput`: why a setting couldn't be read or written, and what a value setting takes
- `DeviceMonitor`: reads what the modem hears as `DeviceMonitorEvent`s, such as a device's group command with what the catalog says it means, in a stream that runs in its reader's task; it records the identities devices report and when each was last heard in the network

The store never holds credentials, the Hub's MAC address, names or rooms.

See the DocC catalog in `Sources/InsteonCore/InsteonCore.docc` for the full documentation.
