# InsteonServer

An optional Swift HTTP service for one Hub or serial modem on macOS 14 or later, or Linux.
The service, HTML pages and request handling are implemented in Swift. There are no client
scripts, required Insteon subscriptions or public cloud relays.

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
password. The Hub's ALL-Link database is read at startup. Use Identify on an unknown device
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

## API

Authenticate every endpoint with the same HTTP Basic credential as the website. There is no
public health, discovery or device endpoint. Authenticated clients may list and control all
devices known by this service. Pairing, individual client tokens and per-device permissions
aren't implemented.

| Method | Path | Behavior |
| --- | --- | --- |
| GET | `/` | Swift-generated HTML, with cached values and explicit POST controls |
| GET | `/api/v1/devices` | `{ "version": 1, "devices": [...] }`; doesn't poll hardware |
| POST | `/api/v1/devices/1A.2B.3C/commands` | Identify, read status, On or Off for a known device's main group |
| GET | `/api/v1/events` | Server-sent JSON events for changes heard after subscription; no history |

JSON commands need `Content-Type: application/json` and `X-Insteon-Request: 1`. Example body:

```json
{"action":"on","levelPercent":50}
```

`action` is `identify`, `status`, `on` or `off`. `levelPercent` is optional, accepted only
for `on`, from 0 through 100, and only when the catalog says the device dims. Unknown fields,
invalid addresses and malformed values are refused. Request bodies are limited to 8 KiB.
Errors use a non-success status and a plain-text explanation without hardware diagnostics.
Browser command failures redirect to the device page with an inline message on the affected
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
page uses manual refresh; native clients can subscribe and request status as needed. Idle event
streams have no heartbeat or replay mechanism, so clients must reconnect and refresh state
after a dropped connection. Event responses end during graceful server shutdown. The HTTP
adapter buffers at most 64 pending events per response; a client that falls behind is
disconnected and must reconnect and refresh state. Requests have no idempotency-key or
deduplication support.

## Persistence and lifecycle

The service writes its own network snapshot at
`$XDG_STATE_HOME/insteon/gateway.json`, or `~/.local/state/insteon/gateway.json`. Use
`--state /absolute/path/gateway.json` for another file. It is separate from the CLI's cache
and contains no credentials. Use a dedicated state file for each configured modem or Hub.
The file is saved after successful operations and during startup and graceful shutdown;
passive events aren't stored as history.

Control-C or SIGTERM stops the HTTP service and closes the hardware session. If the modem's
event stream ends, the server stops. Automatic reconnection and installation as an operating
system service aren't implemented; restart it after correcting the connection. Unexpected
errors are redacted in logs. A corrupt or unsupported state file is refused rather than
overwritten.

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
path. The browser page uses explicit refresh and POST controls; native clients can subscribe
to the event API to observe command completions from other clients.
