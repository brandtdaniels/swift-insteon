# InsteonService

A Swift application service for one persistent Insteon network. It uses InsteonCore's typed
device operations and catalog capabilities. It has no HTTP, authentication, HTML or wire-format
dependencies. The [optional server](../InsteonServer) supplies those adapters.

## Responsibilities

`InsteonService` owns queries, explicit device operations, monitoring, lifecycle and snapshot
policy. Its single admission gate covers all callers; a concurrent operation is refused with
`ServiceControlError.busy` rather than queued. Device lists use cached identities and values,
without polling hardware. Unknown identities expose no switching controls until identified.

`DeviceQuerying`, `DeviceCommanding` and `DeviceEventSource` describe separate client roles;
`InsteonServiceAPI` composes them for adapters that need all three. Commands and events carry
typed addresses. `CommandReceipt` preserves InsteonCore's structured `DeviceStatus`.
An acknowledgment doesn't claim that status was read back. Controls aren't automatically retried.

`SnapshotPersisting` is an optional, replaceable persistence policy. `NetworkSnapshotPersistence`
adapts a network snapshot store. A failed save returns `PersistenceOutcome.failed` separately
from a successful command acknowledgment or reading. It doesn't turn a known hardware result
into an unknown failure.

## Lifecycle

The host opens one modem session and creates a restored `DeviceNetwork`. Call `run` with the
host's asynchronous body: the service prepares the modem, subscribes to monitoring, checkpoints,
and runs the body until it finishes, fails or the connection ends. Shutdown cancels the other
child task and checkpoints again. The host closes the session. No HTTP server is needed to use
this runtime. One controlling service should own each modem.

Snapshots include cached state and identities, not event history. Passive changes remain in
memory until a checkpoint. `lastAnsweredAt` records a device response, not a passive event.
Consumers request status when they need a confirmed reading.

Tests use an in-memory modem and replaceable storage. Physical Hub/modem verification remains
necessary before unattended deployment.
