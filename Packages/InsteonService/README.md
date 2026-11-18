# InsteonService

A Swift application service for one persistent Insteon network. It uses InsteonCore's typed
device operations and catalog capabilities. It has no HTTP, authentication, HTML or wire-format
dependencies. The [optional server](../InsteonServer) supplies those adapters.

## Responsibilities

`InsteonService` owns queries, explicit device operations, monitoring, lifecycle and snapshot
policy. Its single admission gate covers all callers; a concurrent operation is refused with
`ServiceControlError.busy` rather than queued. Device lists use cached identities and values,
without polling hardware, and never take the gate: a list answers while an operation is in
flight, and a list never makes an operation refuse. Unknown identities expose no switching controls until identified.

`DeviceQuerying`, `DeviceCommanding` and `DeviceEventSource` describe separate client roles;
`InsteonServiceAPI` composes them for adapters that need all three. Commands and events carry
typed addresses. `CommandReceipt` preserves InsteonCore's structured `DeviceStatus`.
An acknowledgment doesn't claim that status was read back. Controls aren't automatically retried.

`SnapshotPersisting` is an optional, replaceable persistence policy. `NetworkSnapshotPersistence`
adapts a network snapshot store. A failed save returns `PersistenceOutcome.failed` separately
from a successful command acknowledgment or reading. It doesn't turn a known hardware result
into an unknown failure.

## Lifecycle

A service made with a `NetworkOpening` owns the modem connection. The host creates a
`DeviceNetwork.offline` network over the saved snapshot and calls `run` with its asynchronous
body. The body starts at once. The service opens the modem, reads its ALL-Link database,
monitors it and, when the modem and database read succeed, serves the new network and saves a
snapshot. The cached device list is served throughout.

When the Hub or modem goes away, `run` keeps going. The service refuses commands with
`ServiceControlError.modemUnavailable(cause)` before anything is sent, publishes
`ServiceEvent.modemUnavailable(cause)`, and opens a new connection after a delay that doubles
from 1 second to 60 seconds with up to a quarter taken off at random (`ReconnectPolicy`, from an
injected clock). Rejected credentials (HTTP 401 or 403) wait 15 minutes between attempts, since
the same credentials fail the same way; a Hub that answers with a 5xx status is retried like a
timeout. A configuration error such as a refused Hub address ends the run. When a connection
succeeds, subscribers get `ServiceEvent.modemReconnected` and refresh what they show. A command
that failed because the connection dropped is never repeated by a reconnection.

`health()` reports readiness (`starting` before the first connection, `ready`, `degraded`), the
modem's state and cause, the time of the last hardware exchange and of the last confirmation of
the cached device information. It sends nothing to hardware and doesn't take the admission gate.

A service made with `init(network:persistence:)` leaves the connection to its host, and `run`
ends when that connection does. No HTTP server is needed to use this runtime. One controlling
service should own each modem.

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
a gap. The sequence survives the modem going away and returning, carrying `modemUnavailable`
and `modemReconnected`; a subscriber that arrives while the modem is away is told first. Each
subscription has one reader, and cancellation releases it. Abandoned subscriptions aren't
retained by the service.
Swift clients consume this throwing sequence with `for try await` and handle a gap by
subscribing again and refreshing state.

These completions cover commands sent through this service. Commands issued by another
controller aren't inferred from arbitrary protocol replies. Passive notifications retain their
meaning and don't imply a fresh status reading.
