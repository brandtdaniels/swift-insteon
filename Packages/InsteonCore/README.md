# InsteonCore

Keep track of the Insteon devices on a network: the library an app or a command builds on.

## Types

### Reaching a modem and the catalog

- `ModemSession`: opens a Hub's modem, only at a private IPv4 address, or a PowerLinc Modem on a serial port, and makes the `DeviceNetwork` for it; writes a raw serial command only once `SerialCommandPolicy` allows it
- `SerialCommandPolicy`: which raw serial commands are written, refused unless forced, or never written
- `HubSearch`: finds Hubs on the local network or through Insteon Connect, and identifies them with their credentials
- `ProductCatalog`: the Insteon device catalog, bundled or saved, and its update, which never goes back to an older version
- `InsteonErrorDescription`, `SendFailure`: a message for a person from the lower-level modules' errors, and what a failed send means

### Devices and the network

- `DeviceRegistry`: the devices an app knows, each with the identity it reported and what the Insteon device catalog says about it; it never sends anything to a modem or a device, and describes every device again when given a newer catalog
- `RegisteredDevice`: a device's address, identity and `DeviceInfo`
- `DeviceInfo`: what the catalog says about a device: its product's name and model, the product key it's expected to report, and what its link records' data bytes mean, as `LinkDataMeaning`
- `DeviceRegistrySnapshot`: a registry's devices as a value to save and restore
- `DeviceRegistryStore`: somewhere an app keeps a registry's devices between launches
- `JSONFileDeviceRegistryStore`: keeps them in a versioned JSON file only the current user can read, replaced whole on every save; it also reads the `insteon` command's identity cache, and never replaces a file it can't read
- `DeviceRegistryStoreError`: why the file couldn't be read or written
- `DeviceNetwork`: the devices reached through one modem; lists the modem's ALL-Link database with each device described, hands back a device's ALL-Link database from its copy while the device's delta is the same, and identifies devices, sharing an identification in progress for the same address
- `ModemDatabaseEntry`: a record of the modem's ALL-Link database and the device it names
- `LinkRecord`, `LinkDatabase`: a record of an ALL-Link database, whether it's a controller record and in use, with its group, device, data bytes and memory address; and a device's records with the delta they were read at
- `DeviceProductData`: what a device reported to Product Data Request
- `NetworkSnapshot`: what a network knows, to save and restore: the registry's identities, each device's engine, ALL-Link database copy and delta, last known level and when it last answered, the modem's ALL-Link database, and the Hub's location
- `NetworkDeviceState`: what a network learned about one device besides its identity
- `HubLocation`: the Hub's host, port and Insteon ID, and whether the Hub's credentials may be sent to its host: only to a private IPv4 address, as `ModemSession.withHub` requires
- `NetworkSnapshotStore`: somewhere an app keeps a network's snapshot; `JSONFileDeviceRegistryStore` is one
- `Device`: one device on a network, controlled as the Insteon device catalog describes it; reads its settings and changes them, never writing the flags that turn off its radio or powerline or require a checksum, or any flag or command the Insteon device catalog guards, and only turning its programming lock off, also through a value whose byte holds those flags
- `DeviceSetting`, `DeviceSettingsReading`, `DeviceSettingChange`: a setting with what a settings page shows for it, the settings a device reported, and what a write changed
- `DeviceSettingError`, `DeviceSettingInput`: why a setting couldn't be read or written, and what a value setting takes
- `ProtectedCommand`: Set Operating Flags with the cmd2s that turn most devices' radio or powerline off, require a checksum or turn the programming lock on, sent only to a device whose command set names the cmd2 for a flag it doesn't guard, and Poke, never sent; every message InsteonCore sends is checked against them by its bytes
- `SendRefusal`: why `DeviceNetwork.send(_:collectingFor:onAcknowledgment:)`, which sends a device a message as it's given through the same guards as `Device`, or `ModemSession.write(rawCommand:forcing:collectingFor:clock:)`, which writes a serial command once `SerialCommandPolicy` allows it, refused before sending anything; only a refusal the policy makes unless forced can be forced
- `DeviceCapabilities`: what a device can do, for a front end to decide what to show

### Linking and scenes

- `DeviceLinkingCoordinator`: links, unlinks and removes devices, remotely where the catalog says it works and with their SET buttons otherwise, telling a `LinkingObserver` what to ask a person and what happened
- `LinkMade`: a link the modem reported, with the identity the device sent
- `Instructions`, `InstructionStep`, `ResetErasure`: the catalog's steps for a person on a device, such as to link it or restore its factory settings, and what a reset erases
- `ModemScene`: one of the modem's groups as a scene: its responders, and turning them all on or off, with a `SceneResult` of which acknowledged

### Watching

- `DeviceMonitor`: reads what the modem hears as `DeviceMonitorEvent`s, such as a device's group command with what the catalog says it means, in a stream that runs in its reader's task; it records the identities devices report in the network, and not when a device was heard

The store never holds credentials, the Hub's MAC address, names or rooms.

See the DocC catalog in `Sources/InsteonCore/InsteonCore.docc` for the full documentation.
