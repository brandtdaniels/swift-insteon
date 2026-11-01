# Linking by Writing ALL-Link Databases

Link a device to the modem, or unlink it, by writing the records of its links into both
ALL-Link databases directly, without linking mode or the SET button.

## Overview

Linking with linking mode or a device's SET button, as
``DeviceLinkingCoordinator/link(_:as:group:twoWay:setButtonTimeout:usesCatalogLegs:observer:)``
does, is the default, and the way Insteon's own apps link. Writing the databases directly is
for a device that can't be reached with linking mode but answers the modem, such as one whose
SET button is out of reach or one that keeps falling back to it, and for removing the records
of links whose other half is gone.

A database link is planned first, from a fresh reading of both databases, and carried out
only once the plan is shown and accepted:

```swift
let plan = try await network.linking.planDatabaseLink(lamp)

for step in plan.steps {
  print(step.kind, step.record.memoryAddress as Any, step.record.group)
}

let result = try await network.linking.apply(plan)

if !result.isComplete {
  print(result.mismatches)
}
```

### What a link writes

``DeviceLinkingCoordinator/planDatabaseLink(_:)`` asks the device for its engine and identity,
reads its database and the modem's, and adds whichever records of the Insteon device catalog's
links between the device and a Hub are missing, the responder's record of each link before the
controller's. A record already there stays as it is, data and all, and the plan lists it in
``DatabaseLinkPlan/linksInPlace``. A device's new record goes into its first slot not in use,
then into the slot of the record that marks the end of its database, after the slot below it
is written as the new end, so the database always has an end. No record in use is overwritten.

A responder record the device keeps holds the data bytes the catalog gives for its group: a
fixed value, the device's own group for a byte that holds it, full on for an on-level, and 0.5 s
for a ramp rate. The plan is refused, as a ``DatabaseLinkRefusal``, for a byte the catalog gives
no value for, and for a device the catalog gives no links for.

### What an unlink writes

``DeviceLinkingCoordinator/planDatabaseUnlink(_:removingOrphans:)`` clears the in-use bit of each
of the device's records that names the modem, in its slot, and deletes each of the modem's
records that names the device. ``DatabaseLinkPlan/orphans`` lists the device's records that name
a device the modem has no record of; with `removingOrphans`, they're cleared too, first. No
database is compacted. The modem's records go first and the device's last, so an i2CS device
keeps a record of the modem, which it needs to accept a write, until its last one; it rejects
the modem from then on, so that write can't be read back.

### Which devices

A device that runs i2CS and accepts the modem, as it does once it holds any record of the
modem, takes database writes, and so does one the catalog says runs i2. Nothing is written to
an i1 device, an i2CS device that rejects the modem, or a device whose database fails a
checksum, ends without its end record, or has no room for the records.

### Carrying out a plan

``DeviceLinkingCoordinator/apply(_:)`` reads both databases again and writes nothing when either
changed since the plan. Each step is then made and read back: a device's record from its slot,
and the modem's records for the device in the step's group. A step that reads back differently
is made once more, and only then; when it still reads back differently, or the device doesn't
answer, the steps after it aren't made. Last, both databases are read again and every record is
compared with what the steps that were made should have left, in
``DatabaseLinkResult/mismatches``. Nothing else is sent: no operating flag is read or written,
and no device is put into linking mode.

### Undoing it

A database link is undone with a database unlink of the same device, which removes every record
of a link between it and the modem. An unlink is undone by linking again, by database or with
linking mode; the cleared slots are reused.

## Topics

### Planning

- ``DatabaseLinkPlan``
- ``DatabaseLinkDirection``
- ``DatabaseLinkStep``
- ``DatabaseLinkRefusal``

### Results

- ``DatabaseLinkResult``
- ``DatabaseLinkStepOutcome``
- ``DatabaseMismatch``
