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

## Events

Each `events()` subscription combines named device notifications with `commandCompleted`
events for successful Identify, Read status, On and Off operations performed through this
service. Subscribe before issuing a command. Every completion includes the typed command and
its `CommandReceipt`, including independent persistence health. An On/Off acknowledgment has
no status reading; a Read status completion carries the actual structured reading. No extra
hardware read is sent to produce these events. Failed or refused commands produce no completion.

Completions are published after the cache and persistence result are established. A subscriber
can immediately query the updated cache once the operation releases admission. The sequence
has no replay, buffers at most 64 command completions per subscriber, and throws
`ServiceEventError.slowConsumer` if that subscriber falls behind. Reconnect and refresh after
a gap. The sequence also ends when the modem's event stream ends. Each subscription has one
reader, and cancellation releases both underlying readers. Abandoned subscriptions aren't
retained by the service.
Swift clients consume this throwing sequence with `for try await` and handle a gap by
subscribing again and refreshing state.

These completions cover commands sent through this service. Commands issued by another
controller aren't inferred from arbitrary protocol replies. Passive notifications retain their
meaning and don't imply a fresh status reading.
