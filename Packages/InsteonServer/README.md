# InsteonServer

An optional Swift HTTP service for one Hub or serial modem on macOS 14 or later, or Linux.
The service, HTML pages and request handling are implemented in Swift. A small, locally served
browser helper submits controls in the background and replaces the affected device card.
There are no required Insteon subscriptions or public cloud relays.

A remote client connects through a user-supplied VPN to the home computer running the service.
Only the service connects to the Hub or serial modem. The Hub doesn't need to be routed to
remote clients. The server's dependencies are declared in this directory's `Package.swift`,
outside the root libraries' and existing CLI's dependency graph.

## Run on a home computer

Swift 6.3 or later is required. From the repository root:

```sh
swift run --package-path Packages/InsteonServer insteon-server --help
```

The server reads the CLI's protected `~/.config/insteon/env`, or
`$XDG_CONFIG_HOME/insteon/env`. An explicit `--env-file` can name another file. Process
environment variables take precedence. Use the Hub's local credentials, not an Insteon
account login:

```dotenv
INSTEON_HUB_HOST=192.168.4.50
INSTEON_HUB_PORT=25105
INSTEON_HUB_USERNAME=your-local-hub-user
INSTEON_HUB_PASSWORD=your-local-hub-password
INSTEON_GATEWAY_PASSWORD=replace-with-a-separate-random-password
```

Replace the example address with the Hub's address. Generate the gateway password locally:

```sh
openssl rand -hex 32
```

Put that output in `INSTEON_GATEWAY_PASSWORD`, without sharing or committing it. It must be
32 through 1024 bytes and contain no control characters. The environment file must be owned
by the user running the service and must not be writable by anyone else:

```sh
chmod 700 ~/.config/insteon
chmod 600 ~/.config/insteon/env
```

Start with the loopback listener on port 8080:

```sh
swift run --package-path Packages/InsteonServer insteon-server
```

Open `http://127.0.0.1:8080/` on that computer. Log in as `insteon` using the separate gateway
password. The listener opens at once and serves the saved device list while the Hub's ALL-Link database is read. Use Identify on an unknown device
to learn its capabilities, then Read status, On or Off. A percentage field is shown only when
the main group dims. Device names and controls come from the catalog through InsteonCore.

For remote testing, bind explicitly to the computer's VPN interface address. Replace this
example with that computer's actual VPN IPv4 address:

```sh
swift run --package-path Packages/InsteonServer insteon-server --listen 100.100.20.30
```

Connect the client to the same private VPN, then open `http://100.100.20.30:8080/`. The server
port is independent of the Hub's port. Do not advertise a route to the Hub, forward either
port through the router, or publish a public tunnel. Keep the home computer awake and the
service running. A private listener doesn't itself encrypt HTTP: use the encrypted VPN
path. Wildcard addresses, host names and public listener addresses are refused.

A USB or serial modem uses the same service:

```sh
swift run --package-path Packages/InsteonServer insteon-server --serial /dev/ttyUSB0
```

On macOS, use the modem's actual `/dev/cu.*` path. Run one controlling service per modem;
don't run the CLI's `watch` or other controller processes against the same modem while the
service is active.

## Browser controls

With browser scripting enabled, Identify, Read status, On and Off update only their device
card. Other cards, their edited values and the page's scroll position remain intact. Buttons
on the active card are disabled while a request is pending to prevent repeated submissions.
Errors and persistence warnings appear on that card. A lost response never triggers an
automatic retry, because the device may already have acted.

The helper uses the existing authenticated forms and form protection. Requests marked
`X-Insteon-Fragment: device` receive a Swift-rendered article instead of a redirect. Ordinary
forms remain available without scripting and redirect to an anchor on the affected card.
The helper is served from the authenticated `/controls.js` endpoint, with no external assets,
inline scripts or script evaluation. With live updates connected, successful controls from
other clients refresh the affected card automatically. The live status line shows connection
state. Reconnecting or returning to a backgrounded page refreshes cached information to cover
missed events. Unsaved level inputs, focus and viewport position are preserved; a background
read cannot overwrite an in-flight or newer local command response.

Live synchronization uses authenticated `GET /devices/{address}` card fragments and the cached
device list. Busy or failed cache reads are retried with backoff; stalled reads time out, and
page suspension cancels obsolete reads. Hardware commands are never retried automatically.
No extra hardware command is sent to refresh a card. Physical activity notifications don't
imply a confirmed new reading; use Read status when a fresh hardware reading is needed.

## HTTPS for remote access

For regular remote use, bind the Swift service to loopback and put your private VPN's HTTPS
proxy in front of it. On the Mac, run the service without `--listen`:

```sh
swift run --package-path Packages/InsteonServer insteon-server
```

In another terminal, configure the HTTPS proxy for that local port:

```sh
sudo tailscale serve --bg http://127.0.0.1:8080
```

Follow the HTTPS setup prompt if needed. Use the printed `https://…ts.net` address in the
browser and as the website in your password manager. Authenticate with the same service user
and password. The HTTPS address is restricted to the private VPN; the Swift service and Hub
are contacted locally. Keep the home computer awake and the service running. See the
[HTTPS proxy reference](https://tailscale.com/kb/1312/serve) for installation-specific details.

A direct HTTP connection over the encrypted VPN protects traffic on that VPN path. HTTPS
also supplies a secure browser origin and an address suitable for password-manager launching.

## API

Authenticate every endpoint with the same HTTP Basic credential as the website. There is no
public health, discovery or device endpoint: even the health report is authenticated, because
when the Hub is away is itself information about the household. Authenticated clients may list and control all
devices known by this service. Pairing, individual client tokens and per-device permissions
aren't implemented.

| Method | Path | Behavior |
| --- | --- | --- |
| GET | `/` | Swift-generated HTML, with cached values and explicit POST controls |
| GET | `/api/v1/devices` | `{ "version": 1, "devices": [...], "stale": false, "cause": null }`; doesn't poll hardware. `stale` is `true`, with the `cause`, while the Hub or modem is away |
| GET | `/api/v1/health` | Readiness, modem state, ages; sends nothing to hardware (see Staying up) |
| POST | `/api/v1/devices/1A.2B.3C/commands` | Identify, read status, On or Off for a known device's main group |
| GET | `/api/v1/events` | Server-sent JSON events, numbered; resumes from `Last-Event-ID` (see Event ids and resuming) |
| GET | `/api/v1/openapi.json` | The OpenAPI 3.1 description of every route below, generated from the server's route table |
| GET | `/devices/1A.2B.3C` | Authenticated card fragment from cached state; no hardware polling |

JSON commands need `Content-Type: application/json` and `X-Insteon-Request: 1`. Example body:

```json
{"action":"on","levelPercent":50}
```

`action` is `identify`, `status`, `on` or `off`. `levelPercent` is optional, accepted only
for `on`, from 0 through 100, and only when the catalog says the device dims. Unknown fields,
invalid addresses and malformed values are refused. Request bodies are limited to 8 KiB.
Every failure of an API route is the JSON body described under Errors, without hardware diagnostics.
Ordinary browser form failures redirect to the device page with an inline message on the affected
device's card. Refreshing that page doesn't repeat the command. While the service is busy,
the website retains its last displayed device list so the message and controls remain visible.
Expired or malformed browser forms return to that page with an explanation and send no
device command. The refreshed controls use the active form key.

A successful control returns `outcome: "acknowledged"`, not a claim that status was read
back. A status request returns `outcome: "read"` with a structured `status` object containing
`group`, `kind`, `value`, `isOn` and, where applicable, `percent` or `label`. Clients need not
parse display text. Every receipt reports `persistence` independently: `notConfigured`,
`notAttempted`, `saved` or `failed`. A failed snapshot save preserves a successful HTTP response
and the known device acknowledgment or reading. Browser controls show a save warning.
A network timeout can leave the hardware outcome unknown: read status before deciding whether
to repeat a command. The server doesn't queue or automatically retry controls.
Concurrent controller operations receive 409.

The event stream reports identities, SET button presses, group commands, heartbeats, status
change notifications and explicit service command completions. A `commandCompleted` event has
`address` and a `completion` object containing `action`, optional `levelPercent`, and `result`.
The result has the same receipt shape as the command API, including `outcome`, optional
structured `status`, and independent `persistence`. An acknowledged On/Off isn't a status
readback. Failed or refused commands don't produce a completion, and no extra hardware read
is sent to generate events. These completions cover commands sent through this service.
Subscribe before issuing commands to receive them. Passive events don't imply that cached values have been refreshed. The browser
subscribes to completion and identity events and refreshes affected cards from cached state;
native clients can subscribe and request status as needed. A client that reconnects with the
id of the last event it saw is replayed what it missed, or told to refresh (see Event ids and
resuming). The browser reconnects after any closure with backoff from 0.5 to 30 seconds.

An idle stream carries a `: keepalive` comment every 15 seconds and ends cleanly after 10
minutes, so a client whose network vanished without closing the connection releases its slot;
a browser reconnects at once. At most 16 streams are open at once, and opening one more ends
the oldest. The listener accepts 32 connections, so streams never take more than half. A
connection that sends no complete request within 30 seconds, or whose write doesn't finish
within 30 seconds, is closed. Event responses end during graceful server shutdown. The HTTP
adapter buffers at most 64 pending events per response; a client that falls behind is
disconnected, and reconnects from the last id it saw.

## Event ids and resuming

Each frame of `/api/v1/events` is one event with an SSE `id:` and a JSON `data:` line:

```
id: 9f3a0c41d27e5b86-42
data: {"version":1,"runId":"9f3a0c41d27e5b86","sequence":42,"kind":"commandCompleted", ...}
```

- A **run** is one start of the service, named by `runId`, an opaque token of letters and digits
  that is different at every start. Its events are numbered `sequence` 1, 2, 3 and so on, shared by
  every client: all clients see the same number for the same event. Numbers restart with a new run.
- The `id:` is `<runId>-<sequence>`: the run and the number together, because a number means
  something only with its run. Treat it as opaque and send it back unchanged.
- Every kind of event is numbered: `commandCompleted`, `identified`, `setButtonPressed`,
  `groupCommand`, `heartbeat`, `statusChanged`, `modemUnavailable` and `reconnected`.
- A comment line (`: connected`, `: keepalive`) is not an event and has no id. A new stream with no
  id sent first writes a bare `id:` with the run's current position and no data, so a browser that
  sees no event before it reconnects can still resume.
- The server keeps the newest **256** events in memory, with no age limit. Nothing is written to
  disk, and a restart forgets them.

A client resumes by sending the last id it saw as the `Last-Event-ID` header, which a browser's
`EventSource` does by itself when it reconnects, or as the `lastEventId` query parameter for a
client that can't set headers (the header wins). The stream starts according to the client's id:

| Client's id | The stream starts with |
| --- | --- |
| In this run, and everything after it is still kept | The events after it, in order, then live events. No gap. |
| In this run, but newer events were dropped (`tooOld`), or numbered past the newest (`ahead`) | A `gap` event, then live events. |
| From another run, or not an id the server made (`otherRun`) | A `gap` event, then live events. |
| None | A bare `id:` with the current position, the modem's state if it is away, then live events. |

A `gap` event tells the client it missed events the server can't replay, so it refreshes
everything it shows (the device list and each card) and continues from the events that follow:

```
id: 9f3a0c41d27e5b86-42
data: {"version":1,"kind":"gap","reason":"tooOld","runId":"9f3a0c41d27e5b86","sequence":42}
```

`reason` is `otherRun`, `tooOld` or `ahead`; `runId` and `sequence` are the run's current
position, and the `id:` is the same position. A gap is an ordinary frame, not a named SSE event, so
`EventSource.onmessage` receives it; branch on `kind`. After a gap, an away modem is announced with a
`modemUnavailable` event at the current number.

Resuming doesn't repeat a command and doesn't read hardware. The 10 minute lifetime of a stream
and a client that falls more than 64 events behind both end the stream cleanly; the client
reconnects with its last id and, while the missed events are still kept, resumes without a refresh.
The browser helper refreshes its cards on a gap and on its first connection, not on a resume. A
reconnect after a server restart is a gap, and so replaces the browser's form keys.

## Persistence and lifecycle

The service writes its own network snapshot at
`$XDG_STATE_HOME/insteon/gateway.json`, or `~/.local/state/insteon/gateway.json`. Use
`--state /absolute/path/gateway.json` for another file. It is separate from the CLI's cache
and contains no credentials. Use a dedicated state file for each configured modem or Hub.
The file is saved after successful operations and during startup and graceful shutdown;
passive events aren't stored as history.

Control-C or SIGTERM stops the HTTP service and closes the hardware session. A lost Hub or modem
connection doesn't stop the server; it reconnects as described under Staying up. A corrupt or
unsupported state file is refused rather than overwritten.

## The API contract

`GET /api/v1/openapi.json` (authenticated like every route) returns an OpenAPI 3.1 description of
the server: every route, its parameters and headers (`X-Insteon-Request`, `Idempotency-Key`,
`Last-Event-ID`, and the `Idempotent-Replay` response header), the request and response schemas,
every error code with its HTTP status and `sent` value, and the event stream's frames, including
`gap` and its reasons. The bytes are the same on every request.

The description is generated from the Swift types that implement the server, so it can't drift:
the router registers its routes from the same table the description is built from, the error codes
come from the enumeration the errors use, and the tests encode the real response types and check
that they satisfy the schemas. A browser route (`/`, `/controls.js`, `/devices/{address}`) is listed
under the `browser` tag and isn't part of the versioned contract.

A client app:

- reads the document once, or generates its types from it, and sends it the gateway password with
  any user name (Basic authentication);
- branches on `code` in an error body, never on `message`, and on `sent` before it repeats a command;
- repeats a command it didn't get an answer to with the same `Idempotency-Key`;
- follows `/api/v1/events` with the last id it saw, and refreshes everything it shows on a `gap`;
- ignores fields, event kinds and error codes it doesn't know.

### Versioning

The path carries the version: everything under `/api/v1` keeps the meaning it has. These are
additive, so they happen inside `/api/v1`:

- a new route, or a new optional request field or header;
- a new field in a response or event, and a new value of a field that documents itself as open
  (error `code`, event `kind`, `cause`);
- a new error code, with the status and `sent` its class already has;
- a new event kind, which a client that doesn't know it ignores.

These are breaking and need `/api/v2`:

- removing or renaming a route, a field or an enumeration value, or changing a field's type, range
  or meaning;
- making an optional request field required, or refusing a request that was accepted;
- changing the HTTP status or `sent` of an existing error code, or reclassifying a failure into a
  different code;
- changing the format of an event `id` (`<runId>-<sequence>`) or the rules for resuming from it;
- changing authentication.

A client must tolerate additions. The wording of `message` and the order of keys aren't part of the
contract.

## Errors

Every non-2xx response from a route under `/api/` is JSON with the same shape:

```json
{"version":1,"code":"outcomeUnknown","message":"...","sent":true,"requestId":"..."}
```

- `code` is a stable string to branch on. It never changes meaning inside `/api/v1`.
- `message` is for a person. It carries no device address, host or credential, and its wording
  can change.
- `sent` is `true` only when a command that changes a device may have reached it, so repeating
  the command could repeat the change. A read (status, identify), a refusal before anything was
  sent, and a device's own rejection report `false`: nothing changed, and repeating is safe.
  Only `outcomeUnknown` and a control that was `canceled` report `true`.
- `requestId` is the `request_id` of the log record for the same request.
- `cause` is present only for `modemUnavailable`.

The request log's `code` is the same string, so a client's report and the log line match. The
browser's own routes (`/`, `/devices/{address}`) keep their HTML and plain-text responses with the
same status for the same failure.

| Code | Status | `sent` | When |
| --- | --- | --- | --- |
| `authenticationRequired` | 401 | false | No Authorization header. `WWW-Authenticate` is set. |
| `authenticationFailed` | 401 | false | The password is wrong. |
| `invalidAddress` | 400 | false | The address in the path isn't an Insteon address. |
| `invalidCommand` | 400 | false | The body isn't valid JSON for a command: unknown field, unknown action, wrong type. |
| `invalidLevel` | 400 | false | The percentage is outside 0 through 100, or the device or action doesn't take one. |
| `invalidIdempotencyKey` | 400 | false | The `Idempotency-Key` header is malformed. |
| `unknownDevice` | 404 | false | The service doesn't know the device. |
| `routeNotFound` | 404 | false | No such route. |
| `apiMarkerMissing` | 403 | false | `X-Insteon-Request: 1` is missing. |
| `bodyTooLarge` | 413 | false | The body is over 8 KiB. |
| `unsupportedMediaType` | 415 | false | The content type isn't `application/json`. |
| `requestRejected` | as the transport chose | false | Another malformed request. |
| `busy` | 409 | false | Another command is running. Nothing was queued. |
| `idempotencyKeyReused` | 422 | false | The `Idempotency-Key` was used for a different command. |
| `notIdentified` | 409 | false | The device never reported what it is and doesn't answer, so no control was sent. |
| `notLinked` | 409 | false | The device rejected the modem because it isn't linked to it. |
| `unsupportedControl` | 422 | false | The device has no such control. |
| `deviceRejected` | 422 | false | The device answered with a NAK. |
| `modemRejected` | 503 | false | The modem refused the command (a NAK). |
| `modemUnavailable` | 503 | false | The Hub or modem is away, or the Hub rejected its credentials. `cause` says why; a Hub target that doesn't answer is `hubUnreachable`, a serial modem that doesn't is `modemUnreachable`. |
| `canceled` | 503 | true for a control, false for a read | The request was canceled while it ran. |
| `deviceNotAnswering` | 504 | false | A read got no answer, or failed in the modem. |
| `outcomeUnknown` | 502 | true | A control may have reached the device and no answer proves what happened. Read status before repeating it. |

A client retries on its own judgment: `sent: false` is safe to repeat once the cause is gone;
`sent: true` is not, until status has been read. The server never repeats a command itself.

## Repeating a command safely

A client that doesn't get a response can't tell whether a control reached the device. Send
`Idempotency-Key: <token>` with a command POST, and repeat the same request with the same key to
find out: the server returns the recorded answer and sends nothing.

- The key is a token the client picks, 1 through 128 characters from `A-Z a-z 0-9 . _ ~ : -`, such
  as a UUID. Any other form is `400 invalidIdempotencyKey`. The header is optional; without it every
  request is sent.
- The same key with the same command (device, action and level; JSON key order and spacing don't
  matter) returns the recorded status and body with `Idempotent-Replay: true`. A recorded failure
  carries the repeated request's own `requestId`.
- The same key with a different command or device is `422 idempotencyKeyReused`, and nothing is sent.
- A repeat that arrives while the first is still running waits for its answer and gets it with
  `Idempotent-Replay: true`. It doesn't send a second command.
- What is recorded: a success, and a failure whose `sent` is `true` (`outcomeUnknown`, a canceled
  control). Those are the answers a client can't recreate by asking again. A failure with
  `sent: false` (`busy`, `modemUnavailable`, `notIdentified`, any refusal) is never recorded: nothing
  changed, so repeating it costs nothing, and it may succeed once its cause is gone. After a `409 busy`
  the client repeats the same key.
- Memory is bounded: 256 answers, each kept 10 minutes from when it was recorded. The oldest leaves
  first when the store is full. The record lives in memory only, so a restart forgets it; a client
  that repeats a key after a restart sends the command again, after reading status.
- Keys belong to the authenticated principal. The gateway has one password, so one principal; a
  per-client scope changes the scope, not the rule.
- The server never repeats a command on its own, and browser form posts don't use keys.

## Staying up while the Hub is away

The HTTP listener never depends on the Hub. If the Hub is unplugged, restarting, unreachable
or rejecting the credentials, or a serial modem is unplugged, the server keeps running and
keeps retrying (1 second doubling to 60 seconds, with jitter; 15 minutes after rejected
credentials). Nothing exits the process.

| State | Commands | Device list and page | Events |
| --- | --- | --- | --- |
| Starting (first connection pending) | 503, cause `connecting` or the failure's cause | Saved list, `stale: true` | `modemUnavailable` once a cause is known |
| Hub or modem away | 503, code `modemUnavailable`, `sent: false`, cause and a guided message | Saved list, `stale: true`, banner naming the cause | `modemUnavailable` with `cause` and `message` |
| Back | Work again, no restart | Fresh after the ALL-Link database is read | `reconnected`: clients refresh every card |

A refused command is never queued or repeated, and a reconnection never replays one. The 503
body is `{"version":1,"code":"modemUnavailable","sent":false,"cause":"hubUnreachable","message":"..."}`.
Causes are `connecting`, `hubUnreachable`, `credentialsRejected`, `hubErrorStatus`,
`modemUnreachable` and `connectionLost`. A command that was already sent when the connection
dropped fails with 502, `outcomeUnknown` and `sent: true`; read status before repeating it.

`GET /api/v1/health` needs the same authentication and sends nothing to hardware:

```json
{"version":1,"status":"starting","modem":{"connected":false,"cause":"hubUnreachable"},"lastExchangeAgeSeconds":null,"lastPollAgeSeconds":null,"snapshotAgeSeconds":3600,"persistence":"saved"}
```

`status` is `starting` until the first connection, then `ready` or `degraded`. The ages are in
seconds. `lastExchangeAgeSeconds` is the time since the modem last answered the service or sent
it something, `null` before the first connection; in a quiet house it keeps growing while the
status stays `ready`. `lastPollAgeSeconds` is the time since the Hub last answered a poll of its
buffer. The service polls about twice a second, so while the Hub is reachable it stays small even
when nothing happens, and it grows once the Hub stops answering. It is `null` before the first
answered poll, and always `null` for a serial modem, which isn't polled. Use it, not
`lastExchangeAgeSeconds`, to tell a quiet house from a dead link. `snapshotAgeSeconds` is the
time since the cached device information was last confirmed against the modem's ALL-Link
database; before the first connection it is the age of the saved state file. It reports no device, address or Hub
detail. The endpoint answers 200 whatever the status, so a monitor reads the body.

Wrong Hub credentials are reported as `credentialsRejected`. The service retries every 15
minutes, in case the Hub's password was restored; changing the credentials in the environment
file needs a restart. The log (standard error) says each change, without credentials.

## Run under a supervisor

The server stays up for connection problems, so a restart means a crash or a configuration
error. Let the operating system restart it. `Deployment/insteon-server.plist` (macOS launchd) and
`Deployment/insteon-server.service` (Linux systemd user unit) restart it on failure. They hold
no secrets: the server reads the Hub's and gateway passwords from the protected environment file
(`~/.config/insteon/env`, mode 600), never from the unit file or its command line. Build a release
binary and install it where the unit expects:

```sh
swift build -c release --package-path Packages/InsteonServer
install -m 755 Packages/InsteonServer/.build/release/insteon-server ~/.local/bin/insteon-server
```

For launchd, copy the plist to `~/Library/LaunchAgents/`, replace `YOU`, then
`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/insteon-server.plist`. For systemd, follow
the steps at the top of the unit file.

## Failures and logs

The server writes its log to standard error through swift-log, one line per record. A failure
that stops the server is one critical record: its message names the cause and the setting,
file or device to check, and its metadata carries a stable `code` and the `exit_status`. The
message never contains the Hub's or the gateway's password.

| Exit status | Meaning |
| --- | --- |
| 78 | A setting, option or file to change: options, the environment file, credentials the Hub rejects, a missing serial path, the state file. |
| 69 | A port that isn't available, or a serial modem path that can't be opened for another reason. |
| 1 | An error the server doesn't recognize. The message names its type only. |

A Hub or modem that doesn't answer never stops the server, so it never has an exit status. The
log says each change instead, with the same codes and wording: one record at warning level when
the Hub or modem goes away or its cause changes (`hub_unreachable`, `hub_answered_with_error`,
`modem_unreachable`, `modem_connection_ended`), one at error level for rejected credentials
(`hub_credentials_rejected`), and one at info level with `code=modem_connected` when it
returns. A retry that fails the same way logs nothing; an outage that lasts is repeated every 15
minutes with `reminder=true`. A setting, option, file or port that can't work, a refused Hub
address and a serial path that doesn't exist at start still end the server with their message
and exit status.

Each HTTP request writes one record with its `method`, `route`, `status`, `duration_ms`,
`request_id` and a stable `code`, plus a `cause` when a command fails in the Hub or modem.
The `route` is the matched template, such as `/api/v1/devices/{address}/commands`, or
`unmatched`; the path, query, headers, body and Authorization value are never logged, so a
mistyped password and a client's own text can't reach the log. A `duration_ms` covers the time
until the response starts, so an event stream records its connection, not its length. A request
without credentials logs `authenticationRequired` at info level, a wrong password logs
`authenticationFailed` at warning level, and a refused command logs a warning. The log doesn't
summarize or rate-limit failed authentication.

The server is a prototype for local and private VPN testing. Tests cover a real local HTTP
listener and an in-memory modem. macOS and physical hardware validation are still required
before relying on it unattended.

## Validation

```sh
swift build --package-path Packages/InsteonServer --build-tests --explicit-target-dependency-import-check error -Xswiftc -warnings-as-errors
swift test --package-path Packages/InsteonServer --skip-build
```

## Architecture

- `InsteonService` (root library): typed device queries, commands, events, lifecycle and one
  admission gate shared by all callers. It depends on InsteonCore and knows no HTTP or HTML.
- `SnapshotPersisting`: replaceable persistence policy. The file-store adapter reports storage
  outcomes independently of hardware outcomes.
- `InsteonHTTP` (optional target): HTTP authentication and middleware, versioned JSON DTOs,
  API routing, browser form handling and a separate HTML renderer. Both commands and event
  streams use the same injected service. Authentication can be replaced independently.
- `InsteonServerSupport`: composition and configuration. Opens the hardware session, restores
  state, creates the service and adapters, and hosts HTTP during the service runtime.
- `insteon-server`: executable entry point and safe error reporting.

Transport models are separate from domain models. The query, command and event protocols let
adapters depend on the roles they use. A different host can use the service without the HTTP
package. Existing environment keys and state paths retain their names for compatibility.

## Remote test from a phone

Keep the home computer awake and the service running on its private VPN IPv4 address. Connect
the phone to the same VPN, turn off the phone's Wi-Fi, and open the service's printed HTTP URL
in the phone's browser. Authenticate with the separate server credential, then use Read status
and a chosen test device's controls. Restore the device's original state after testing.

The phone connects to the home service, and the service connects locally to the Hub. No Hub
subnet route, router port forwarding or public tunnel is required. The VPN encrypts the remote
path. The browser page subscribes to the event API and updates cards when other clients complete
commands. Native clients can consume the same events.
