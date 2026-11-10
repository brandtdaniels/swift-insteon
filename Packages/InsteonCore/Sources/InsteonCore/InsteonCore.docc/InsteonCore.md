# ``InsteonCore``

Keep track of the Insteon devices on a network, for an app or a command to build on.

## Overview

InsteonCore is the library a front end depends on, such as an app or the `insteon` command.
It keeps the devices an app knows and what the Insteon device catalog says about each.

A front end needs no other module. ``ModemSession`` opens a Hub's modem or a PowerLinc Modem,
``HubSearch`` finds Hubs, ``ProductCatalog`` loads and updates the Insteon device catalog, and
``InsteonErrorDescription`` describes the lower-level modules' errors. Links and what the
catalog says are InsteonCore's own types, such as ``LinkRecord``, ``DeviceInfo`` and
``Instructions``, so a front end doesn't decode record flags or read the catalog's schema.
Values that are only data, such as `InsteonAddress` and `ReportedIdentity`, are the
lower-level modules' types under the same names, declared in InsteonCore. Some initializers
for an app that brings its own modem or catalog, such as ``DeviceNetwork``'s, take lower-level
types, such as `LinkingModem` from InsteonLinking and `DeviceCatalog` from
InsteonDeviceCatalog.

```swift
import InsteonCore

try await ModemSession.withHub(host: host, port: HubLocation.defaultPort, user: user, password: password) { session in
  let network = session.network(catalog: catalog, snapshot: NetworkSnapshot(), hub: session.hub)

  try await network.device(lamp).turnOn(level: 50)
}
```

``ModemSession/withHub(host:port:user:password:_:)`` sends the Hub's user name and password,
which the Hub's plain HTTP carries readably, only to an IPv4 address in `10.0.0.0/8`,
`172.16.0.0/12` or `192.168.0.0/16`. A host name, an IPv6, loopback or link-local address, and
a public address are refused with ``HubAddressRefused`` before anything is sent, and
``HubLocation/acceptsCredentials`` checks a host as it's entered. Requests go to the Hub
directly, never through a proxy.

A ``DeviceRegistry`` holds each device's address and the identity it reported: its category,
subcategory and firmware version. It describes every device with the catalog, and describes
them all again when it's given a newer catalog, so no device is lost when the catalog
changes. The registry never sends anything to a modem or a device; record what a device
reports, and look it up later by its address:

```swift
let registry = network.registry

await registry.record(identity, for: lamp)

if let known = await registry.device(lamp) {
  print(known.info.displayName ?? "unknown product")
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
let network = session.network(catalog: catalog, snapshot: try store.loadNetwork(), hub: session.hub)

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

A group whose state shares a command with other groups, such as each of a sprinkler's zones in
its valve status, is on only when the reply's bits match the pattern the catalog gives it, so
each zone reads on its own. A load made of outputs, such as a dimmer's two relays while a mode
flag is set, lists them in ``DeviceGroup/outputs``, and
``Device/turnOn(outputs:group:)`` and ``Device/turnOff(outputs:group:)`` switch them by their
bits, once the device reports the operating flag state the catalog names. An alarm or arming
group lists its ``DeviceGroup/armModes``.

``DeviceCapabilities`` says what to show for a device: its groups, whether it dims or beeps,
and its settings with their controls. ``Device/readSettings(includingAdvanced:beforeReading:)``
reads the settings, and ``Device/writeSetting(_:to:button:)`` changes one and reads it back.
Each ``DeviceSetting`` carries what a settings page needs from the catalog: its label,
section, whether it's advanced, its control, and its default as each reading's entry shows it.
A write can change other settings too, as some devices turn a flag on when a value that isn't
zero is written, so the device's other writable settings are read before the write and again
once it's confirmed, each request once; a reading or a value nothing writes changes on its
own, so it's left out. ``DeviceSettingChange/changedSettings`` lists each one whose value
differs, ``DeviceSettingChange/unreadSettings`` each one the device didn't report again, and
``DeviceSettingChange/OtherSettings`` says how the comparison ended, and why the other settings
couldn't be read again after a write that succeeded.

The Insteon device catalog says which settings are guarded. A flag it guards with
`FlagGuard.keep`, such as one that turns off a device's radio or powerline or requires a
checksum in every message, any of which can cut the device off from the modem, is never
written: it's shown as read-only, and writing one throws
``DeviceSettingError/neverWritten(label:)``, as does writing a setting whose command the
catalog guards with `CommandGuard.never`. A flag it guards with `FlagGuard.neverSet`, such as
one that locks linking from the device itself, is only ever turned off, so a device is never
left locked; turning it on throws ``DeviceSettingError/leavesProgrammingLocked(label:)``. The
same holds for a value whose byte holds those flags, which the catalog marks with
`SettingValue.flagsQuery`, and for the guarded bits of an extended command's flags parameter:
it's refused before it's written when it would set a bit that's never set or change one that's
kept. Under every guard is a floor of bytes, the ``ProtectedCommand``s. Set Operating Flags
with cmd2 `0x0C`, `0x0E`, `0x19` or `0x00` is refused for a device the catalog doesn't know or
gives no command set, and for a command set that doesn't name the cmd2; it's sent only where
the command set names it for a flag or command it doesn't guard, such as a keypad's button
lock flag, turned on with `0x19`; a command set that names a protected cmd2 through an
unguarded entry unlocks it. Poke is never sent. ``ProductCatalog`` refuses a saved or
supplied catalog, and its update a downloaded one, unless, for every device either catalog
knows and every firmware version, the command set the catalog gives the device is at least as
strict as the bundled copy's by these same rules, as `DeviceCatalog.guardWeakenings(comparedTo:)`
lists them: the bytes never sent, the protected cmd2s refused, the guarded bits of each flags
query, the guarded bits of every byte written on each extended Set selector or extended
command route, by where the byte is read, each value's guarded bits and
`SettingValue.flagsQuery`, and the guarded commands. A device the bundled copy doesn't know,
or gives no command set, counts as one with none, so a catalog may give it a command set that
unlocks no protected cmd2. Linking changes, keep-awake messages and relay state holding
aren't compared, and a `DeviceCatalog` handed to
``DeviceNetwork/init(modem:catalog:snapshot:hub:timeout:clock:now:)`` is used as given. A flag is shown as writable when at least
one of its states is sent. Every message a ``Device`` sends is checked by the bytes it carries,
after any value is filled in, whatever setting, command or action built it: on every route an
extended message writes a byte, a never-set bit isn't set, and a kept bit matches the byte the
device reported where its value is read, or, for a message not built from that report, any
guarded bit, kept or never set, refuses it; an extended Set whose selector the command set
doesn't list, or to a device with no command set, is refused whatever built it; and the Set Operating Flags bytes that turn a kept flag on or off or
a never-set flag on, and those of a command the catalog guards, are never sent under any name,
and the operation throws
``DeviceControlError/unsupported(_:product:)``. A value a setting doesn't
take throws an error with a ``DeviceSettingInput`` that says what it takes:

```swift
do {
  let change = try await lamp.writeSetting("rampRate", to: "0.5 s")
  print("\(change.title): \(change.before ?? "?") to \(change.after ?? "not confirmed")")
  for other in change.changedSettings {
    print("Also changed: \(other.title): \(other.before) to \(other.after)")
  }
} catch DeviceSettingError.neverWritten(let label) {
  print("\(label) can't be changed.")
}
```

### Checking a device

``Device/selfTest(_:)`` checks that a device is healthy and set up as the catalog expects, and
returns a ``SelfTestReport`` of ``SelfTestCheck``s in the order they ran: the device answers
and accepts the modem, the catalog describes the identity it reports in the test, it reports
the product key the catalog gives its product, it reports its state, its ALL-Link database,
read from the device rather than from a copy the network holds, ends whole, with every
checksum intact for an i2CS device, it and the modem hold both records of each link the
catalog gives it, its records name only the modem and devices the modem is linked to, and no
operating flag locks it or cuts it off. A damaged record isn't taken for a missing link. A
link the catalog says covers every group the device controls while an operating flag is in a
state is checked group by group, each check naming its ``SelfTestGroup``, with the flag as
the device reported it. Each check has a ``SelfTestOutcome``, a sentence saying what it found, and the
``SelfTestFix``es that may put it right, from Insteon's troubleshooting steps, for a front end
to say how to carry out. The test only reads; ``SelfTestOptions/actuates`` also sends Beep when
the catalog lists a Beep that's sent to the device. A device that doesn't answer fails the
first check, and the rest are skipped. ``SelfTestReport/checklist`` lists what only a person
can check, such as pressing a button or cutting the device's power, for a front end to show
once, after the checks:

```swift
let report = try await network.device(lamp).selfTest()

for check in report.checks where check.outcome != .passed {
  print(check.title, check.detail)
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

When the catalog gives a device's linking from a Hub as legs, linking it by its address makes
each leg's link in the catalog's order, as a ``HubLinkingLeg``: the modem starts ALL-Linking
first in the leg's role and group, the device joins with Enter Linking Mode for its group or
with its SET button, as the catalog says, and the coordinator waits for ALL-Linking Completed
before the next leg. ``DeviceLinkingResult/legs`` says what became of each:

A battery-powered device the catalog says how to keep awake is sent that message through the
device's guarded send path, before linking or after its first link, and the message that lets
it sleep again once linking ends, even when it fails or is canceled. A
``LinkingObserver`` asks a person to wake it first when the message goes before linking.

```swift
for outcome in result.legs {
  print(outcome.leg.modemRole, outcome.leg.modemGroup, outcome.link != nil)
}
```

A relay records its state as it links: a group On then sets it to that state and a group Off
to the opposite. How the relay holds a state comes from the catalog, in its group type's
`stateHolding`: the flags that keep it from holding one, the state it returns to by itself, and
the flags with which every On and Off only pulses it. A relay the catalog says nothing about is
refused.
``DeviceLinkingCoordinator/linkRelay(_:recording:group:twoWay:setButtonTimeout:observer:)``
puts the relay in a chosen ``RelayState`` first, turning off a flag that keeps it from holding
a state when the catalog lets linking change it, links, reads the record back, and puts back
what it changed however linking ends. ``DeviceLinkingCoordinator/link(_:as:group:twoWay:setButtonTimeout:usesCatalogLegs:observer:)``
never switches a relay:

```swift
let result = try await network.linking.linkRelay(relay, recording: .off, group: 2, observer: prompter)

// `nil` when every On and Off only pulses the relay, so the state is ignored.
print(result.relayState?.groupOn.map(\.rawValue) ?? "ignored")   // off
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

### Writing ALL-Link databases

``DeviceLinkingCoordinator/planDatabaseLink(_:relayState:)`` and
``DeviceLinkingCoordinator/planDatabaseUnlink(_:removingOrphans:)`` plan the writes that link a
device to the modem, or unlink it, by writing both ALL-Link databases directly, from a fresh
reading of each, and write nothing. ``DeviceLinkingCoordinator/apply(_:)`` carries a plan out,
reading each write back. <doc:DatabaseLinking> says what each writes and when to use it.

### Sending bytes as they're given

A front end that explores what the catalog doesn't describe yet sends a device a message as
it's given with ``DeviceNetwork/send(_:collectingFor:onAcknowledgment:)``, and writes the
modem a serial command with ``ModemSession/write(rawCommand:forcing:collectingFor:clock:)``.
Both check the bytes first, and throw a ``SendRefusal`` before anything is sent. A message is
checked like every message a ``Device`` sends, and a serial command by
``SerialCommandPolicy``, which finds the ``ProtectedCommand``s in any message to a device or
a group it holds. Nothing forces a ``ProtectedCommand`` through; `forcing` writes only a
serial command the policy refuses unless it's forced:

```swift
do {
  _ = try await session.write(rawCommand: bytes, collectingFor: .seconds(3))
} catch let refusal as SendRefusal where !refusal.canBeForced {
  print("Never written: \(refusal)")
}
```

## Topics

### Controlling devices

- ``Device``
- ``DeviceCapabilities``
- ``DeviceGroup``
- ``DeviceGroupKind``
- ``DeviceOutput``
- ``DeviceFlagCondition``
- ``DeviceStatus``
- ``DeviceTurnOnResult``
- ``DeviceTurnOffResult``
- ``DeviceInstantChangeResult``
- ``DeviceBeepResult``
- ``DeviceOperation``
- ``DeviceControlError``

### Checking devices

- ``SelfTestReport``
- ``SelfTestCheck``
- ``SelfTestCheckKind``
- ``SelfTestGroup``
- ``SelfTestOutcome``
- ``SelfTestFix``
- ``SelfTestChecklistItem``
- ``SelfTestOptions``

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
- ``DeviceProductData``
- ``ModemScene``
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
- ``HubLinkingLeg``
- ``HubLinkingJoin``
- ``HubLinkingLegStatus``
- ``HubLinkingLegOutcome``
- ``KeepAwakeEvent``
- ``WakePrompt``
- ``RelayState``
- ``RelayStateEvent``
- ``RelayLinkPlan``
- ``RelayStateLink``
- ``RelayStateLinkingError``
- ``LinkedDevice``
- ``UnlinkedLink``
- ``RemovedLinks``
- ``TwoWayLinking``
- ``DeviceLinkingResult``
- ``DeviceUnlinkingResult``
- ``DeviceUnlinkingAllResult``
- ``RemoteUnlinkingError``

### Writing ALL-Link databases

- <doc:DatabaseLinking>
- ``DatabaseLinkPlan``
- ``DatabaseLinkResult``

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

### Opening a modem

- ``ModemSession``
- ``SendFailure``
- ``HubFailure``
- ``HubAddressRefused``
- ``InsteonErrorDescription``

### Finding Hubs

- ``HubSearch``
- ``HubCandidate``
- ``HubSource``
- ``LocalHubSearch``
- ``HubIdentification``

### The Insteon device catalog

- ``ProductCatalog``
- ``ProductCatalogUpdate``
- ``ProductCatalogUpdateError``
- ``ProductCatalogError``
- ``ProductCatalogStore``
- ``ProductCatalogStoreError``

### Raw passthroughs

- ``ProtectedCommand``
- ``SendRefusal``
- ``SerialCommandPolicy``
- ``DirectMessage``
- ``ReceivedFrame``
- ``RawModemReply``

### Values

- ``InsteonAddress``
- ``AllLinkGroupNumber``
- ``DeviceCategory``
- ``DeviceSubcategory``
- ``FirmwareVersion``
- ``ProductKey``
- ``InsteonEngine``
- ``ReportedIdentity``
- ``ModemInfo``
- ``NAKReason``
- ``LinkRecord``
- ``LinkDatabase``
- ``LinkMade``
- ``SceneResult``
- ``AllLinkMode``
- ``ModemLink``
- ``ModemRole``
- ``ManualLinkingRole``
- ``LinkingDirection``
- ``DeviceInfo``
- ``ExpectedProductKey``
- ``LinkDataMeaning``
- ``LinkDataField``
- ``Instructions``
- ``InstructionStep``
- ``ResetErasure``
- ``DeviceCatalogVersion``
