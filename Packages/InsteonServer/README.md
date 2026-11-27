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
environment variables take precedence. The server serves one Hub: run one server per Hub,
each with its own `--env-file` (the CLI's `hubs/NAME.env` files are written in the same form, and a Hub Pro's file holds only its `INSTEON_HUB_HOST`).
Use the Hub's local credentials, not an Insteon
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

Authenticate every endpoint with the gateway password (HTTP Basic, as the website does) or, on
the API routes, with a client token (see Clients, scopes and pairing). There is no public health,
discovery or device endpoint: even the health report is authenticated, because when the Hub is
away is itself information about the household. A credential may list and, with the `control`
scope, command all devices known by this service. Per-device permissions aren't implemented.

| Method | Path | Behavior |
| --- | --- | --- |
| GET | `/` | Swift-generated HTML, with cached values and explicit POST controls |
| GET | `/api/v1/devices` | `{ "version": 1, "devices": [...], "stale": false, "cause": null }`; doesn't poll hardware. `stale` is `true`, with the `cause`, while the Hub or modem is away |
| GET | `/api/v1/health` | Readiness, modem state, ages; sends nothing to hardware (see Staying up) |
| POST | `/api/v1/devices/1A.2B.3C/commands` | Identify, read status, On or Off for a known device's main group |
| GET | `/api/v1/events` | Server-sent JSON events, numbered; resumes from `Last-Event-ID` (see Event ids and resuming) |
| GET | `/api/v1/openapi.json` | The OpenAPI 3.1 description of every route below, generated from the server's route table |
| GET, POST | `/api/v1/clients` | List the clients, or create one and its pairing document (`admin`) |
| DELETE | `/api/v1/clients/{id}` | Revoke a client (`admin`) |
| POST | `/api/v1/clients/{id}/pairing` | Replace a client's credential and return its pairing document (`admin`) |
| GET | `/api/v1/notification-rules` | List the notification rules (`read`; see Notifications) |
| PUT, DELETE | `/api/v1/notification-rules/{id}` | Store or remove a rule (`admin`) |
| GET | `/api/v1/schedules` | List the schedules with their next runs (`read`; see Schedules and timers) |
| PUT, DELETE | `/api/v1/schedules/{id}` | Store or remove a schedule (`admin`) |
| GET | `/api/v1/timers` | List the timers that haven't fired (`read`) |
| PUT, DELETE | `/api/v1/timers/{id}` | Start, restart or cancel a timer (`admin`) |
| GET | `/api/v1/routes` | List the routes transport plugins registered (`read`; see Writing a plugin) |
| PUT, DELETE | `/api/v1/routes/{kind}` | Register or remove a transport's route (`admin`) |
| GET | `/api/v1/backup` | A backup of the cached network, the format `insteon backup` writes (`admin`; see Backups) |
| GET | `/api/v1/scenes` | The scenes of the network from the cached ALL-Link databases (`read`; see Scenes) |
| POST | `/api/v1/scenes/{number}/commands` | Turn a scene the modem controls on or off (`control`; see Scenes) |
| POST | `/api/v1/scenes/refresh` | Read the ALL-Link databases from the hardware, then list the scenes (`control`; see Scenes) |
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

## Clients, scopes and pairing

The gateway password is one credential for the whole household, and it can't be taken back from
one phone without changing it everywhere. A client is its own credential: a name, a scope and a
token that the service can revoke alone.

| Scope | Allows |
| --- | --- |
| `read` | List devices, read health, follow events, read the API description. |
| `control` | Everything `read` allows, and send commands to devices. |
| `admin` | Everything `control` allows, and create, list, revoke and re-pair clients. |

The gateway password acts as `admin`, so nothing that works with it changes. A client token goes
in `Authorization: Bearer <token>`, on the API routes only. The browser routes (`/`,
`/controls.js`, `/devices/{address}`) take the gateway password only and keep their form key
protection. Each operation in the OpenAPI description lists the least scope it needs, so the route
table is the one place a scope is decided: an operation can't be added without one. A client
whose scope is too low gets `forbidden` (403, `sent` false) and nothing reaches a device. A
token that is wrong, altered or revoked gets `authenticationFailed`, the same as a wrong password.

| Method | Path | Behavior |
| --- | --- | --- |
| GET | `/api/v1/clients` | The clients: `id`, `name`, `scope` and `createdAt`. Never a token. |
| POST | `/api/v1/clients` | Body `{"name":"Phone","scope":"control"}`. Creates a client and returns `{ "version": 1, "client": {...}, "pairing": {...} }`, where `pairing.credential` is the token. |
| DELETE | `/api/v1/clients/{id}` | Revokes the client: 204. |
| POST | `/api/v1/clients/{id}/pairing` | Gives the client a fresh credential and returns the pairing document. |

All four need the `admin` scope, `X-Insteon-Request: 1`, and for the POST that creates a client,
`Content-Type: application/json`. The service keeps at most 64 clients. A name is 1 through 64
characters without control characters, and two clients may share one.

### Pairing

A pairing document is one JSON object that carries a credential and the ways to reach the
service. A QR code, a link or a file can carry it, and a client reads it the same way each time.

```json
{
  "version": 1,
  "serviceId": "3f2a0c5d9e8b4a71b6d0c2e4f8a91357",
  "name": "Network",
  "credential": "<the client's token, shown once>",
  "scope": "control",
  "api": "/api/v1",
  "routes": [
    { "kind": "lan", "url": "http://insteon.local:8080" }
  ]
}
```

A client tries `routes` in order and uses the first that answers `GET /api/v1/health` with the
credential. It skips a route `kind` it doesn't know and ignores fields it doesn't know, so a
transport or a field can be added inside version 1. `serviceId` is chosen once and stays with the
service, so a client can tell two homes apart. The `lan` route is `http://LISTEN:PORT` from
`--listen` and `--port`, or `--advertise-url` when the address a client uses differs, such as a
name the router resolves. The service never binds a public address, so a route that crosses the
internet is a `kind` that a separate transport process supplies: it registers the route with the
service, and each document issued after a registration lists it after the `lan` route (see Writing a plugin).

```sh
swift run --package-path Packages/InsteonServer insteon-server pair --name Phone --advertise-url http://insteon.local:8080
```

`pair` creates a `control` client (`--scope read|control|admin` chooses another), prints the
document, and on a terminal follows it with a QR code. `--no-qr` prints the document only, and
output that isn't a terminal never has the code. Run it with the same `--state` as the server: it
writes the client file, and a running server recognizes the client at once. It needs neither the
gateway password nor a modem. A document that is too long for a QR code, which holds about 2,900
bytes, is printed without one.

### Keeping tokens safe

- A token is `<id>.<secret>`. The secret is 32 bytes from the operating system's secure random
  generator, shown once, in the creation response or the `pair` output.
- The service keeps a salted SHA-256 of the secret, never the token. The comparison reads every
  byte, whatever the first difference. A token can't be recovered from the service.
- The clients live in `<state>-clients.json` beside the state file, readable only by the current
  user: `gateway.json` has `gateway-clients.json`. The state file's own format and its promise to
  hold no credentials stay as they are. A client file that can't be read, or is in a format this
  server doesn't know, is left as it is and the server stops with `client_file_unusable`; move it
  aside to start with no clients.
- No log record, error body or message carries a token or the password. The request log records a
  route and a code, as before.

### Revoking and rotating

`DELETE /api/v1/clients/{id}` takes effect at once. The client's next request is refused with
`authenticationFailed`, and its open event streams end, so a lost phone stops receiving events
without waiting for its stream's 10-minute limit. A pairing document made for it is useless from
then on, whichever route it names.

`POST /api/v1/clients/{id}/pairing` rotates: the client keeps its id, name and scope, its old
token stops working, its open streams end, and the response is a document with the fresh token.
To replace a lost device, revoke its client and pair a new one. To change what a client may do,
revoke it and create another with the other scope: a scope never changes in place.

To rotate the gateway password itself, change `INSTEON_GATEWAY_PASSWORD` and restart the server;
clients are unaffected.

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
  `groupCommand`, `heartbeat`, `statusChanged`, `notification`, `modemUnavailable` and `reconnected`.
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

## Notifications

The service evaluates notification rules against what devices report, and publishes a `notification`
event on `/api/v1/events` each time one fires. It sends nothing itself: a separate process, a notifier,
follows the stream and delivers the notification by push, email or webhook. The service never holds a
push credential or opens a connection out of the house.

### Rules

| Method | Path | Behavior |
| --- | --- | --- |
| GET | `/api/v1/notification-rules` | `{ "version": 1, "rules": [...] }`, in the order they were added (`read`) |
| PUT | `/api/v1/notification-rules/{id}` | Adds the rule, or replaces the rule with that identifier (`admin`) |
| DELETE | `/api/v1/notification-rules/{id}` | Removes the rule, which stops firing at once (`admin`) |

A write needs `Content-Type: application/json` and `X-Insteon-Request: 1`. The identifier is in the path:
letters, digits, `-`, `_` and `.`, at most 64 characters. The body is the rule without it, and unknown
fields are refused:

```json
{
  "name": "Basement leak",
  "trigger": { "kind": "event", "event": "wet", "device": "1A.2B.3C" },
  "cooldownSeconds": 300,
  "enabled": true,
  "includeDetail": false
}
```

- `name`: 1 through 64 characters, without control characters.
- `trigger`: `{ "kind": "event", "event": "wet", "device": "1A.2B.3C" }` fires when the device reports an
  event its product's catalog profile names, in lower camel case. When the catalog has a profile for the
  device, the event must be one it names. `{ "kind": "groupCommand", "command1": 19, "group": 5,
  "device": "1A.2B.3C" }` fires when the device sends that command to that group (1 through 255), for a
  product whose profile names no event for it. A heartbeat is not a group command here.
- `cooldownSeconds`: 0 (the default) through 604800. After a rule fires it stays quiet for this long.
- `enabled`: `true` by default. A disabled rule never fires.
- `includeDetail`: `false` by default (see Content-free by default).

The device must be one the service knows, and the service keeps at most 64 rules. Rules take effect on the
next device report, with no restart. Replacing a rule with one that has the same trigger, such as renaming
it, keeps its cooldown running; a different trigger starts afresh. Removing or disabling a rule stops it
at once.

Rules are kept in `<state file name>-notification-rules.json` beside the state file (for the default
state file, `gateway-notification-rules.json`), readable only by the current user and replaced atomically
on each change. A change is saved before it applies, so a failed save changes nothing and answers
`notificationRulesNotSaved`. A file the server can't read, or that is in a newer format, is left as it is
and the server refuses to start; move it aside to start with no rules. Cooldowns are kept in memory, and
a restart forgets them.

Four error codes are added: `invalidNotificationRule` (400), `unknownNotificationRule` (404),
`notificationRuleLimitReached` (409) and `notificationRulesNotSaved` (500). A rule for a device the service
doesn't know is `unknownDevice`. See Errors.

### The event

```
id: 9f3a0c41d27e5b86-43
data: {"version":1,"runId":"9f3a0c41d27e5b86","sequence":43,"kind":"notification","ruleId":"basement-leak","ruleName":"Basement leak","address":"1A.2B.3C","firedAt":"2027-01-15T08:00:00Z"}
```

A `notification` is numbered and kept like every other event, so `Last-Event-ID` resumes it, and a client
that fell behind the newest 256 events gets a `gap` instead of missing one silently. The browser page
ignores it.

#### Content-free by default

A notification carries the rule's identifier and name, the device's address and the time, and nothing
else. A rule with `includeDetail: true` adds `name`, the event that fired it, such as `wet`. A notifier
that sends a message out of the house puts no more in it than the rule's name and the time unless the
person turned detail on.

### Writing a notifier

A notifier is an ordinary client of the stream (Writing a plugin has a reference notifier and a walkthrough):

1. Create a `read` client (`POST /api/v1/clients`) and give the notifier its token.
2. Follow `GET /api/v1/events` with `Authorization: Bearer <token>`, and act only on frames whose `kind`
   is `notification`. Ignore every other kind, and any field or kind it doesn't know.
3. Deliver once. Record the id of the last notification delivered, and send it as `Last-Event-ID` when
   reconnecting. The server replays what was missed, so the notifier delivers a notification only when its
   id is newer than the one it recorded in the same `runId`.
4. A `gap`, or an id from another run, means notifications may have been missed. Keep the recorded id as
   the run's new position and decide whether to tell the person. Delivery that fails is the notifier's to
   retry; the service is not waiting for it.

### Versioning

Everything here is additive inside `/api/v1`: three routes, four error codes and one event kind, with
optional response fields on events. A client that doesn't know `notification` ignores it, as the browser
page does. Changing a field's meaning, the content-free default or the event id needs `/api/v2`.

## Schedules and timers

The service runs schedules and timers itself, with no cloud, so a home keeps its routines when the internet is
down and after a Hub is replaced. A schedule sends a device command at a time on chosen days; a timer sends one
after a delay. An action is one of the service's own commands, turn a device's main group on (at a percentage for
a device that dims) or off, sent the way a client's command is. Reading needs the `read` scope and changing needs `admin`.

| Method and path | What it does |
| --- | --- |
| `GET /api/v1/schedules` | `{ "version": 1, "schedules": [...] }`, each with `nextRun` (`read`) |
| `PUT /api/v1/schedules/{id}` | Adds the schedule, or replaces the one with that identifier (`admin`) |
| `DELETE /api/v1/schedules/{id}` | Removes it, which stops at once (`admin`) |
| `GET /api/v1/timers` | `{ "version": 1, "timers": [...] }`, each with `dueAt` and `remainingSeconds` (`read`) |
| `PUT /api/v1/timers/{id}` | Starts the timer, or restarts the one with that identifier (`admin`) |
| `DELETE /api/v1/timers/{id}` | Cancels it (`admin`) |

```sh
curl -X PUT http://127.0.0.1:8080/api/v1/schedules/porch -u insteon:"$INSTEON_GATEWAY_PASSWORD" \
  -H 'X-Insteon-Request: 1' -H 'Content-Type: application/json' \
  -d '{"name":"Porch light","when":{"time":{"kind":"sunset","offsetSeconds":-900},"weekdays":["monday","tuesday"]},"action":{"device":"1A.2B.3C","action":"on","levelPercent":80}}'
```

`when.time` is `{"kind":"clock","hour":18,"minute":30}`, or `{"kind":"sunrise"}` or `{"kind":"sunset"}` with an
`offsetSeconds` of at most 12 hours either way. `weekdays` defaults to every day. A schedule is checked when it is stored:
the device is known and offers the action (on and off, and a percentage only for a device that dims), a sun time needs
a location, and a clock time needs a time zone the host has. The service keeps at most 64 schedules and 64 timers.

### Time zone and location

`--time-zone NAME` (an IANA name such as `America/Los_Angeles`) and `--latitude` and `--longitude` say where the home is.
The server remembers what it was started with in the schedules file, so a later start without them keeps them, and a
start with a new time zone recomputes every schedule from its wall-clock time. Without a time zone the computer's is used.
Without a location, sunrise and sunset schedules are refused with `locationNotConfigured`. A time zone the host's
time zone database doesn't have is not guessed at: clock times are refused with `timeZoneUnavailable`, and
`GET /api/v1/health` lists it under `notes`.

### Daylight saving time

A clock time is wall-clock time in the home's time zone, converted each day with the host's time zone database, so a
schedule follows daylight saving changes with no edit:

- A time that doesn't exist on the night the clocks spring forward (02:30 when 02:00 becomes 03:00) runs once, when the
  skipped span ends (03:00). In a zone with a half-hour change it runs when that half hour ends.
- A time that happens twice on the night the clocks fall back (01:30) runs once, at its first occurrence.
- Sunrise and sunset are worked out in UTC for the date and shown in local time, so they need no special case.
- A timer counts elapsed time, so a change of the clock neither lengthens nor shortens it.

### Missed runs

A run happens when the service handles it less than a minute after its time. If the service was stopped across a run
time, or the clock was set past it, the run is skipped and reported as `missed`; it isn't replayed. A schedule with
`"catchUp": true` still runs when it is less than 15 minutes late. A run is never retried: when the Hub or modem is away
the run is reported `unavailable`, and the next day's run is unaffected. An edit takes effect at once and keeps nothing of the
old schedule's last run.

### Timers across a restart

A timer is stored with the time it has left. A restart picks up what a graceful stop saved, so a timer set for 5 minutes
that ran for 2 fires 3 minutes after the restart. A server that stopped without saving restarts a timer with the time it
had when it was last stored.

### The event

Each run publishes a numbered `schedule` event on `/api/v1/events` with `scheduleId`, `name`, `source` (`schedule` or
`timer`), the device as `address`, `outcome`, `firedAt` and `nextRun` (null for a timer). `outcome` is `acknowledged`,
`missed`, `unavailable` (`cause` says why), `refused` (`reason` is the error code the same command would answer with) or
`unknown` (the command may have reached the device). The browser page ignores the event.

### What a Hub's own clock does and doesn't do

The service never writes a clock, a schedule or a time zone to a Hub, a modem or a device, and an Insteon device keeps no
schedule of its own that the service sets. A Hub Pro reports its local time in its settings; the service reads it when it
connects and adds a `hubClockDrift` health note when it differs from the service's by more than a minute. The Hub's clock
doesn't run the service's schedules, and a Hub's own schedules, which depended on the vendor's cloud for its clock and
daylight saving changes, are neither read nor changed.

### Versioning

Everything here is additive inside `/api/v1`: four routes, nine error codes, one event kind, a `notes` field on health,
and the options above. A client that doesn't know `schedule` ignores it.

## Writing a plugin

Remote access and notification delivery aren't features of the service. Each is a separate process that
speaks the HTTP contract, so any transport works with any front end and a plugin can be written in any
language. A plugin can't crash or stall the service, because it shares nothing with it but the contract.
The service never binds a public address and holds no push credential: a transport carries bytes to the
service's loopback port, and a notifier turns events into deliveries.

Two reference plugins in this package show each seam. They are small on purpose, and they use the same
routes and the same credentials a plugin in another language would.

| Target | What it is |
| --- | --- |
| `InsteonPluginKit` | The HTTP client, route registration, event stream reader, `Notifier` and `Deliverer` the reference plugins share. Foundation only. |
| `InsteonLoopbackTransport` | The forwarder and the transport built on it. Depends on SwiftNIO and `InsteonPluginKit`. |
| `insteon-reference-transport` | Forwards a loopback port to the service and registers it as the `loopback` route. |
| `insteon-reference-notifier` | Follows the event stream and appends one line per notification to a file or standard output. |

None of them depends on the service's own targets, and the service and the `insteon` command don't depend
on them. The libraries are products, so a Swift plugin can depend on them.

### Writing a transport

A transport accepts connections from where the client is, carries them to the service, and tells the
service how a client reaches it. The service lists that in the pairing documents it issues.

1. Create an `admin` client for the transport (`POST /api/v1/clients`, or `insteon-server pair --scope admin`).
   Registering a route changes what every later pairing document says, so it needs `admin`.
2. Carry each connection to the service's loopback port. Forward bytes, don't read HTTP: then
   authentication and scopes, `Idempotency-Key` replay, and event streams that stay open and resume with
   `Last-Event-ID` behave exactly as on the LAN, and a connection that drops resumes with the last id.
3. Register the route with `PUT /api/v1/routes/{kind}` and the body `{"ticket":"..."}`. Remove it with
   `DELETE /api/v1/routes/{kind}` when the transport stops. A transport that dies without removing its route
   leaves a hint a client will skip; registering the same kind again replaces the ticket in place.

| Method | Path | Behavior |
| --- | --- | --- |
| GET | `/api/v1/routes` | `{ "version": 1, "routes": [ { "kind": "...", "ticket": "..." } ] }`, in the order they were registered (`read`) |
| PUT | `/api/v1/routes/{kind}` | Registers the route, or replaces the ticket of the route with that kind and keeps its place (`admin`) |
| DELETE | `/api/v1/routes/{kind}` | Removes the route (`admin`) |

A write needs `Content-Type: application/json` and `X-Insteon-Request: 1`. The `kind` is the transport's
identifier: 1 through 32 lowercase letters, digits and `-`, starting with a letter, and not `lan`, which is
the service's own. The service keeps at most 8 routes, in `<state file name>-routes.json` beside the state
file, readable only by the current user and replaced atomically on each change, so a registration survives a
restart. A file the server can't read, or that is in a newer format, is left as it is and the server refuses
to start with `routes_file_unusable`; move it aside to start with none.

**A ticket is an opaque locator.** It is 1 through 1024 printable ASCII characters without spaces, and only
the transport that registered it reads it: an address, a node identifier, a capability URL. The service
never interprets it. A ticket is not a secret and not a credential. A client still needs its own token
whatever route it takes, and any `read` client can list the tickets. Keep anything that grants access out
of a ticket.

Every pairing document the service issues after a registration lists the registered routes after the `lan`
route, in registration order, and so does `insteon-server pair`, which reads the same file. A document
issued earlier is unchanged and keeps working: routes are hints a client tries in order, so a client
that holds an older document reaches the service by the routes it has, and learns of a new transport when
it pairs again. A client skips a kind it doesn't know.

### Writing a notifier

A notifier is a client with a `read` token that follows `GET /api/v1/events`. The steps are under
Notifications, Writing a notifier. In short:

- Act only on `notification` frames and ignore every other kind.
- Record the id of the last event you handled and send it as `Last-Event-ID` when you reconnect, so a
  restart delivers nothing twice. The reference notifier records it after the delivery, so a crash between
  the two repeats at most that one notification.
- On a `gap` (or an id from another run), notifications may have been missed and can't be replayed.
  Re-list the rules with `GET /api/v1/notification-rules`, tell the person if you choose to, and continue
  from the id of the `gap` frame.
- Retry a failing delivery with backoff. The service never waits for a notifier.
- Put no more in a message than the rule's name and the time unless the person opted into detail.

The reference notifier takes a `Deliverer` (`deliver(_ payload: DeliveryPayload) async throws`), a state
store and a clock, so its backoff is tested without waiting. Its default deliverer appends the time and
the rule's name, separated by a tab, as one line to a file or standard output. `--include-detail` adds
the device and the event.

### Try the reference plugins

With the server running on `127.0.0.1:8080`, from the repository root:

```sh
BASE=http://127.0.0.1:8080
create() { curl -s -u "insteon:$INSTEON_GATEWAY_PASSWORD" -H 'X-Insteon-Request: 1' \
  -H 'Content-Type: application/json' -d "{\"name\":\"$1\",\"scope\":\"$2\"}" $BASE/api/v1/clients; }

# One client per plugin, each with the least scope it needs. Keep the tokens out of your shell history.
create Transport admin | jq -r .pairing.credential > transport.token
create Notifier read   | jq -r .pairing.credential > notifier.token
create Phone control   | jq -r .pairing.credential > phone.token

# Start the transport. It prints the loopback port it forwards from and registers its route.
INSTEON_PLUGIN_TOKEN=$(cat transport.token) \
  swift run --package-path Packages/InsteonServer insteon-reference-transport --service $BASE
```

In another terminal, read the route the transport registered, and pair a client again. The new document
lists the route after the `lan` route:

```sh
curl -s -H "Authorization: Bearer $(cat notifier.token)" $BASE/api/v1/routes
# {"routes":[{"kind":"loopback","ticket":"127.0.0.1:54321"}],"version":1}

curl -s -u "insteon:$INSTEON_GATEWAY_PASSWORD" -H 'X-Insteon-Request: 1' -H 'Content-Type: application/json' \
  -d '{"name":"Tablet","scope":"control"}' $BASE/api/v1/clients | jq -c .pairing.routes
# [{"kind":"lan","url":"http://127.0.0.1:8080"},{"kind":"loopback","ticket":"127.0.0.1:54321"}]
```

Reach the service through the transport instead of the service's own port. The answers are the ones the LAN
gives, including the typed refusals:

```sh
PORT=54321
curl -s -H "Authorization: Bearer $(cat phone.token)" http://127.0.0.1:$PORT/api/v1/health
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:$PORT/api/v1/health      # 401, no credential
curl -s -H "Authorization: Bearer $(cat notifier.token)" -H 'X-Insteon-Request: 1' \
  -H 'Content-Type: application/json' -d '{"action":"on"}' \
  http://127.0.0.1:$PORT/api/v1/devices/1A.2B.3C/commands                            # {"code":"forbidden","sent":false,...}
```

Follow events through the transport, then resume from the last id you saw. Stop the transport (Control-C) and
the route disappears from `/api/v1/routes`, while the service keeps serving its own port:

```sh
curl -s -N -H "Authorization: Bearer $(cat phone.token)" http://127.0.0.1:$PORT/api/v1/events
curl -s -N -H "Authorization: Bearer $(cat phone.token)" -H 'Last-Event-ID: 9f3a0c41d27e5b86-43' \
  http://127.0.0.1:$PORT/api/v1/events
```

Add a notification rule (see Notifications), then run the notifier:

```sh
INSTEON_PLUGIN_TOKEN=$(cat notifier.token) swift run --package-path Packages/InsteonServer \
  insteon-reference-notifier --service $BASE --state notifier-state.json --output deliveries.log
# deliveries.log: 2027-01-15T08:00:00Z<TAB>Basement leak
```

Stop it and start it again: it resumes from `notifier-state.json` and delivers nothing it already delivered.
Both plugins read their token from `INSTEON_PLUGIN_TOKEN`, never from an argument, and never print it.

### Plugin versioning

Everything in this section is additive inside `/api/v1`: three routes, four error codes, and no change to an
existing response. A client or plugin written against an earlier `/api/v1` keeps working. Specifically:

- A pairing document gains only entries in `routes` and stays version 1. A client ignores a route kind it
  doesn't know and a field it doesn't know.
- A new transport is a new `kind`. It needs no change to the service, to the clients that don't know it, or
  to the other transports.
- A transport or notifier reads the contract from `/api/v1/openapi.json`, which lists these routes, their
  scopes and their error codes, generated from the same table that serves them.
- The routes file and the notifier's state file are versioned (`"version": 1`). A file in a newer format is
  left as it is rather than rewritten.
- Changing the meaning of a ticket, the registration order, or the `lan` route being first needs `/api/v2`.

## Backups

`GET /api/v1/backup` (`admin`) answers with the same document format `insteon backup` writes, as JSON with a `checksum`: the modem's address and ALL-Link database, each device's ALL-Link database, name and identity, the notification rules, the routes and the schedules (each without the time it runs next). Timers are left out, because a timer is a countdown and not configuration. It answers from the cache and sends nothing to the Hub or modem, so a device the service holds no ALL-Link database copy for is listed with the reason `notCached`; run `insteon backup` for a backup that reads each device. The document holds no gateway password, client token or Hub address. A rules, routes or schedules file that can't be read fails the request with `notificationRulesNotSaved`, `routeRegistrationsNotSaved` or `schedulesNotSaved`, rather than leaving it out.

```sh
curl -s -H "Authorization: Bearer $(cat admin.token)" $BASE/api/v1/backup > home.json
insteon backup --check home.json
```

## Scenes

`GET /api/v1/scenes` (`read`) lists the scenes of the network: each group the modem controls (`writable`) and each group a device controls (read only, because the modem can't run or change it), with the devices that respond to it and the three link data bytes each holds. It answers from the ALL-Link databases the service has cached and sends nothing to the Hub or modem. `whole` is false, and the reason is listed, while a device's database is not held (`unreadable`, each entry an `address` and the `reason` it is not held), a record names a device with no database (`unlisted`), the modem's database is not held (`modemUnread`) or a record has no other half (`halfLinks` of a scene, `looseHalfLinks`). A listing that is not whole is never shown as complete.

Each member also carries what its three data bytes mean, as the Insteon device catalog gives them for the identity the service has recorded for that device: `bytes` lists each byte's `name`, `label`, `value`, the `valueName` where the catalog names the value, and `verification`, how sure the catalog is (`observed`, `documented`, `inferred` or `conflicting`). A member the catalog doesn't describe has `described: false` and no `bytes`; its raw `data` is always there. `undescribedMembers` lists the devices with at least one such member. `described: false` also holds while a device's identity has not been read yet or no catalog is loaded, so it can change once the service identifies the device.

```sh
curl -s -H "Authorization: Bearer $(cat read.token)" $BASE/api/v1/scenes
```

`POST /api/v1/scenes/refresh` (`control`, with `X-Insteon-Request: 1` and no body) reads the ALL-Link database of the modem and of each device from the hardware, one request at a time, and answers with the same JSON as `GET /api/v1/scenes` lists after the read. It only reads: nothing is written to the modem or to a device. A device that does not answer is listed under `unreadable`, and the refresh still succeeds with `whole: false`. The `reason` is `noAnswer` (it timed out), `modemStoppedEchoing` or `hubStoppedAnswering` (the modem did not confirm sending the request, or the Hub stopped answering), `rejectedModem` (the device turned the modem away, as an i2CS device does until it is linked to it), `damagedRecords` (the checksums failed on both reads), `failed` (another error), or `notCached` (no refresh has tried it since the service started). The reasons are kept in memory until the next refresh and are not saved, so a restart reports `notCached` until a refresh runs. The service logs one warning for each device a refresh left unread, with its address and reason. A device is asked once, and one that does not answer costs the modem's own time out (about 25 seconds on a Hub 2), so a refresh with several silent devices takes that long for each; cancel the request to stop it between devices. A device whose copy still matches the delta it reports is not read again. The read holds the service's one admission gate for as long as it lasts, so another operation, or a second refresh, is refused as `busy` and nothing is queued. While the modem is not connected it answers `modemUnavailable` before sending anything. A Hub Pro does not give out its ALL-Link databases, so it answers `databasesUnavailable` (422). A refresh that fails midway is safe to repeat (`sent: false`).

```sh
curl -s -X POST -H "Authorization: Bearer $(cat control.token)" -H "X-Insteon-Request: 1" $BASE/api/v1/scenes/refresh
```

`POST /api/v1/scenes/{number}/commands` (`control`, with `X-Insteon-Request: 1` and `Content-Type: application/json`) runs a scene the modem controls. The body is `{"action": "on"}` or `{"action": "off"}` and nothing else: a level is refused as `invalidCommand`, because each member recalls the on-level its own link data holds. The service sends the scene's ALL-Link group one Light On at full level or one Light Off through the modem and waits for the modem's ALL-Link cleanups. It sends nothing to a device and does not read the members afterward, so `GET /api/v1/devices` keeps the levels it held until a device is read or reports.

The answer is a receipt: `scene`, `action`, `outcome` (`acknowledged`, meaning the modem acknowledged sending the group command), `acknowledged` and `unacknowledged` (the members that did and did not acknowledge their cleanup; one that did not may still have acted), `isComplete` (the modem's report that it reached every member), `responderCount` and `persistence`. A modem that passes no per-member acknowledgment up, as a Hub 2 does not, leaves `acknowledged` empty and carries its report in `isComplete`. An empty `acknowledged` never means that no member acted.

A number that is not a group from 1 through 254 is `invalidScene` (400). A number the service has not read, or a group a device controls, is `unknownScene` (404); a scene with no members is `sceneEmpty` (422). Nothing is sent for either. While the modem is not connected it answers `modemUnavailable` before sending anything, and while another operation holds the service's gate it answers `busy`. If the modem refuses the command it answers `modemRejected` (`sent: false`); if the modem accepts it and then stops answering, it answers `outcomeUnknown` with `sent: true`. The service never sends a scene command twice by itself. With an `Idempotency-Key` header a repeat of the same run returns the recorded answer with `Idempotent-Replay: true` and sends nothing; a refusal that sent nothing is not recorded. A scene number is a canonical decimal, such as `3`: `005` and `+5` are `invalidScene`. Each run that completes publishes a numbered `scene` event on `/api/v1/events` with `scene`, `name` (null while a scene has no name), `source` (`api`), `action`, `acknowledged`, `unacknowledged`, `isComplete` and `firedAt`. A run that ends in `outcomeUnknown` (the modem accepted the command and stopped answering) also publishes a `scene` event, with `isComplete` false and empty `acknowledged` and `unacknowledged`, so a client reads the members again. A run refused before anything is sent publishes nothing. A scene run by a member's button or by the command line is not reported, because the modem does not report its own group sends.

```sh
curl -s -X POST -H "Authorization: Bearer $(cat control.token)" -H "X-Insteon-Request: 1" -H "Content-Type: application/json" -d '{"action":"off"}' $BASE/api/v1/scenes/3/commands
```

## Persistence and lifecycle

The service writes its own network snapshot at
`$XDG_STATE_HOME/insteon/gateway.json`, or `~/.local/state/insteon/gateway.json`. Use
`--state /absolute/path/gateway.json` for another file. It is separate from the CLI's cache
and contains no credentials. Use a dedicated state file for each configured modem or Hub.
The file is saved after successful operations and during startup and graceful shutdown;
passive events aren't stored as history. The schedules, the timers and the home's time zone and location are kept in
`gateway-schedules.json` beside it (mode 600, written atomically); a file the server can't read stops it before it
listens and is left as it is.

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
- a new credential kind or scope, as long as every credential that worked keeps working and every
  operation keeps the scope it needed;
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
- revoking what a credential could do: requiring a higher scope for an operation, or dropping a
  credential kind;
- changing how the gateway password authenticates.

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
| `authenticationFailed` | 401 | false | The password or token is wrong, altered or revoked. |
| `forbidden` | 403 | false | The credential's scope doesn't allow the operation. Nothing was sent. |
| `invalidClient` | 400 | false | A client needs a name of 1 through 64 characters and a scope of `read`, `control` or `admin`, and no other field. |
| `unknownClient` | 404 | false | No client has that id. |
| `clientLimitReached` | 409 | false | The service keeps at most 64 clients. |
| `clientsNotSaved` | 500 | false | The client file couldn't be read or written, so nothing changed. |
| `invalidNotificationRule` | 400 | false | A rule needs a name of 1 through 64 characters, a valid trigger and cooldown, and no other field. |
| `unknownNotificationRule` | 404 | false | No rule has that id. |
| `notificationRuleLimitReached` | 409 | false | The service keeps at most 64 rules. |
| `notificationRulesNotSaved` | 500 | false | The rules file couldn't be read or written, so nothing changed. |
| `invalidSchedule` | 400 | false | A schedule needs a name, at least one weekday, a clock time or a sunrise or sunset offset of at most 12 hours, an on or off action, and no other field. |
| `invalidTimer` | 400 | false | A timer needs a name, a delay of 1 through 604800 seconds, an on or off action, and no other field. |
| `unknownSchedule` | 404 | false | No schedule has that id. |
| `unknownTimer` | 404 | false | No timer has that id. |
| `scheduleLimitReached` | 409 | false | The service keeps at most 64 schedules. |
| `timerLimitReached` | 409 | false | The service keeps at most 64 timers. |
| `locationNotConfigured` | 409 | false | A sunrise or sunset schedule needs the server's `--latitude` and `--longitude`. |
| `timeZoneUnavailable` | 409 | false | The configured time zone isn't in the host's time zone database, so a time of day can't be worked out. |
| `schedulesNotSaved` | 500 | false | The schedules file couldn't be read or written, so nothing changed. |
| `invalidRouteRegistration` | 400 | false | A route needs a `kind` of 1 through 32 lowercase letters, digits and `-` that starts with a letter and isn't `lan`, a `ticket` of 1 through 1024 printable ASCII characters without spaces, and no other field. |
| `unknownRouteRegistration` | 404 | false | No route is registered for that kind. |
| `routeRegistrationLimitReached` | 409 | false | The service keeps at most 8 routes. |
| `routeRegistrationsNotSaved` | 500 | false | The routes file couldn't be read or written, so nothing changed. |
| `invalidAddress` | 400 | false | The address in the path isn't an Insteon address. |
| `invalidCommand` | 400 | false | The body isn't valid JSON for a command: unknown field, unknown action, wrong type. |
| `invalidLevel` | 400 | false | The percentage is outside 0 through 100, or the device or action doesn't take one. |
| `invalidIdempotencyKey` | 400 | false | The `Idempotency-Key` header is malformed. |
| `unknownDevice` | 404 | false | The service doesn't know the device. |
| `invalidScene` | 400 | false | The scene number is not a group from 1 through 254. |
| `unknownScene` | 404 | false | The service holds no scene of that number that the modem controls. |
| `sceneEmpty` | 422 | false | The scene has no members, so nothing was sent. |
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
| `databasesUnavailable` | 422 | false | The network doesn't give out its ALL-Link databases, as a Hub Pro doesn't, so a scenes refresh has nothing to read. |
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

## Serving a Hub Pro

`insteon-server --hub ADDRESS` serves a Hub Pro the same way, when no `INSTEON_HUB_USERNAME` and `INSTEON_HUB_PASSWORD` are set: a Hub Pro has no user name or password, and a host that answers as one is served through its local HTTP interface. The API, the website and the errors are the same.

- The server asks the Hub Pro one request at a time, because a Hub Pro can stop answering under load. It reads the Hub Pro's settings and device list when it connects, and describes each device so the catalog can describe it.
- A Hub Pro sends nothing on its own, so the server polls every device's level at an interval and publishes a device event when a level changes. `--poll-interval SECONDS` sets it: 5 seconds by default and 2 at the least. A change made at a device is seen at the next poll.
- A command is sent once and only when the Hub Pro lists it for the device. One the Hub Pro doesn't confirm is `outcomeUnknown` with `sent: true`, and is never sent again.
- A Hub Pro that doesn't answer is `hubUnreachable`, like a Hub, and the server reconnects by itself. A failed poll is how it finds out.
- The server never adds or removes a device on a Hub Pro, changes a link or starts an update: use the Hub Pro's SET buttons to add or remove a device. Scenes, groups, settings and ALL-Link databases aren't offered for a Hub Pro.

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
| 78 | A setting, option or file to change: options, the environment file, credentials the Hub rejects, a missing serial path, the state file, the client file. |
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
without credentials logs `authenticationRequired` at info level, a wrong password or token logs
`authenticationFailed` at warning level, a credential whose scope is too low logs `forbidden`, and
a refused command logs a warning. The log doesn't
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
  API routing, browser form handling and a separate HTML renderer. Clients, scopes and
  pairing documents live here too: the route table gives each operation its scope. Both commands and event
  streams use the same injected service. Authentication can be replaced independently.
- `InsteonServerSupport`: composition and configuration. Opens the hardware session, restores
  state, creates the service and adapters, and hosts HTTP during the service runtime.
- `insteon-server`: executable entry point and safe error reporting.
- `InsteonPluginKit`, `InsteonLoopbackTransport`, `insteon-reference-transport` and
  `insteon-reference-notifier`: the reference plugins. They speak the HTTP contract and depend on
  nothing above, and nothing above depends on them, so the service builds and ships without them.

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
