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

When another process can save to the same store while a network runs, read the store again
and save it merged with only what the network changed since it started, with
``NetworkSnapshot/merging(changesFrom:to:)``, so the other process's newer values are kept.

### Controlling devices

A ``Device`` from ``DeviceNetwork/device(_:beforeIdentifying:)`` is the one way a front end
controls a device. What it can do comes from the Insteon device catalog's group types for the
device: whether a level means anything to a group, which command turns it on or off, and how
to read its state, as a level in percent, the name of a range such as a fan speed, or on or
off. A device the catalog doesn't describe is controlled by its category, as a dimmer or a
relay, and any other one can only be pinged and have its status read as a raw byte. Status,
and turning a device on or off, record its level and when it answered in the network's
snapshot:

```swift
let lamp = network.device(InsteonAddress(0x1A, 0x2B, 0x3C))

let result = try await lamp.turnOn(level: 50)
let status = try await lamp.status()

if try await lamp.capabilities().canDim {
  print("Dims, and is at \(status.percent ?? 0)%.")
}
```

``DeviceCapabilities`` says what to show for a device: its groups, whether it dims or beeps,
and its settings with their controls. ``Device/readSettings(includingAdvanced:beforeReading:)``
reads the settings, and ``Device/writeSetting(_:to:button:)`` changes one and reads it back.
Each ``DeviceSetting`` carries what a settings page needs from the catalog: its label,
section, whether it's advanced, its control, and its default as each reading's entry shows it.

Some settings are never written: turning off a device's radio or powerline, and requiring a
checksum in every message, any of which can cut the device off from the modem, and any other
flag the catalog guards with `FlagGuard.keep`. They're shown as read-only, and writing one
throws ``DeviceSettingError/neverWritten(label:)``, as does writing a setting whose command
the catalog guards with `CommandGuard.never`. The programming lock, and any flag the catalog
guards with `FlagGuard.neverSet`, is only ever turned off, so a device is never left locked;
turning it on throws ``DeviceSettingError/leavesProgrammingLocked(label:)``. The same holds for
a value whose byte holds those flags, such as an open/close sensor's configuration byte, which
the catalog marks with `SettingValue.flagsQuery`, and for the guarded bits of an extended
command's flags parameter: it's refused before it's written when it would set a bit that's
never set or change one that's kept. The radio, powerline, checksum and programming lock flags
are guarded even where the catalog gives no guard; the catalog adds guards, and never removes
these. A catalog that names a flags byte's query differently from the floor is checked against
both. Every message a ``Device`` sends is checked by the bytes it carries, after any value is
filled in: the Set Operating Flags bytes that turn a kept flag on or off or a never-set flag on,
those of a command the catalog guards, and those of a command named for one of these, such as
`programmingLockOn`, are never sent under any name, and the operation throws
``DeviceControlError/unsupported(_:product:)``. A value a setting doesn't
take throws an error with a ``DeviceSettingInput`` that says what it takes:

```swift
do {
  let change = try await lamp.writeSetting("rampRate", to: "0.5 s")
  print("\(change.title): \(change.before ?? "?") to \(change.after ?? "not confirmed")")
} catch DeviceSettingError.neverWritten(let label) {
  print("\(label) can't be changed.")
}
```

### Watching what the modem hears

``DeviceNetwork/monitor`` hands out a ``DeviceMonitor``, whose
``DeviceMonitor/changes(includingRaw:)`` stream reads what the modem hears as
``DeviceMonitorEvent``s: which device sent a command to which group, what the device's profile
in the Insteon device catalog says it means, whether it turns the group on or off, and the
product's name. A device is known from the identities the network's registry holds and from
any identity a device reports while the stream runs, which the monitor records in the
registry. It records nothing else: not when a device was heard, which for a sensor would be a
record of what happens in a home, so a device's last-seen time stays the time it last
answered a command. The stream runs in its reader's task, one task at a time, and ends when
that task is canceled or the modem's replies finish:

```swift
for await event in await network.monitor.changes() {
  if case let .groupCommand(command) = event, command.event == "wet" {
    print("\(command.device) detected water")
  }
}
```

A front end that shows the modem's bytes asks for them with `includingRaw`, which adds each
message's bytes before its events and the kind of each reply that isn't otherwise reported.

### Linking devices

``DeviceNetwork/linking`` hands out a ``DeviceLinkingCoordinator``, which links devices to the
modem and unlinks them, one at a time, and keeps the network's registry, cache and snapshot up
to date as it does. The Insteon device catalog decides what each device needs: whether it's
turned on before it links, the steps a person takes on it, and whether it's linked back so
the modem hears it. A ``LinkingObserver`` gets each ``LinkingEvent`` to show, and asks a
person to put a device into its mode when the device goes first:

```swift
let result = try await network.linking.link(lamp, as: .controller, group: 0, observer: prompter)

if let failure = result.linkBackFailure {
  print("Linked one way only: \(failure)")
}
```

``DeviceLinkingCoordinator/remove(_:scan:forceModemSide:timeout:observer:)`` removes a device
from the network: every link between it and the modem, with the modem's group 0 last, then,
once the modem's ALL-Link database has no links with it, the network forgets it. A device
with links left is kept, and ``DeviceRemovalResult/keptBecause`` says why. Asked to, it reads the other devices' ALL-Link databases and reports
the records that still name the device, without changing them. It ends with the catalog's
factory reset steps, as ``FactoryResetSteps``, for a person to follow; it never resets the
device:

```swift
let removal = try await network.linking.remove(lamp, scan: true, observer: prompter)

for step in removal.factoryReset?.procedure?.steps ?? [] {
  print(step.text)
}
```

## Topics

### Controlling devices

- ``Device``
- ``DeviceCapabilities``
- ``DeviceGroup``
- ``DeviceGroupKind``
- ``DeviceStatus``
- ``DeviceTurnOnResult``
- ``DeviceTurnOffResult``
- ``DeviceInstantChangeResult``
- ``DeviceBeepResult``
- ``DeviceOperation``
- ``DeviceControlError``

### Device settings

- ``DeviceSetting``
- ``DeviceSettingControl``
- ``DeviceSettingsReading``
- ``DeviceSettingChange``
- ``DeviceSettingError``
- ``DeviceSettingInput``
- ``DeviceSettingFieldProblem``

### Devices

- ``DeviceRegistry``
- ``RegisteredDevice``

### Networks

- ``DeviceNetwork``
- ``ModemDatabaseEntry``
- ``NetworkDeviceState``
- ``HubLocation``

### Watching devices

- ``DeviceMonitor``
- ``DeviceMonitorEvent``
- ``DeviceGroupCommand``
- ``DeviceSetButtonPress``
- ``DeviceMessageSummary``
- ``ModemNotice``

### Linking devices

- ``DeviceLinkingCoordinator``
- ``LinkingObserver``
- ``LinkingEvent``
- ``LinkingFallback``
- ``ModemLinksPurpose``
- ``SETButtonPrompt``
- ``DeviceFirstPrompt``
- ``LinkLeg``
- ``LinkedDevice``
- ``UnlinkedLink``
- ``RemovedLinks``
- ``TwoWayLinking``
- ``DeviceLinkingResult``
- ``DeviceUnlinkingResult``
- ``DeviceUnlinkingAllResult``
- ``RemoteUnlinkingError``

### Removing devices

- ``DeviceRemovalResult``
- ``ForgottenDevice``
- ``DeviceKeptReason``
- ``ModemRecordDeletionReason``
- ``LeftoverRecordScan``
- ``LeftoverRecords``
- ``UnreadDatabase``
- ``FactoryResetSteps``

### Keeping devices

- ``DeviceRegistrySnapshot``
- ``DeviceRegistryStore``
- ``NetworkSnapshot``
- ``NetworkSnapshotStore``
- ``JSONFileDeviceRegistryStore``
- ``DeviceRegistryStoreError``
