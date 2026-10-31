# ``InsteonHubClient``

Control Insteon devices through an Insteon Hub on your local network.

## Overview

An Insteon Hub has a built-in Insteon modem that it exposes through a local HTTP interface. ``HubConnection`` turns that interface into a `ModemConnection`, so a `Modem`
from InsteonModem drives a Hub exactly as it drives a USB or serial PowerLinc Modem, with the
same pacing, retries and stream of replies.

```swift
import InsteonHubClient
import InsteonModem
import InsteonProtocol

let hub = Hub(
  endpoint: HubEndpoint(host: "192.168.1.20"),
  user: username,
  password: password
)

// Polls the Hub for replies while the closure sends commands.
try await Modem.withConnection(HubConnection(hub: hub)) { modem in
  let lamp = InsteonAddress(0xAA, 0xBB, 0xCC)

  // Returns once the lamp's acknowledgment shows up in the Hub's buffer.
  try await modem.request(StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF)))
}
```

### How the Hub is polled

The Hub collects the modem's replies in a ring buffer rather than pushing them. While its
stream is read, for example by `Modem.withConnection`, ``HubConnection`` reads the buffer every half
second by default, using a ``HubBufferCursor`` to pick out only the bytes
that arrived since the last read, and sends one request to the Hub at a time. Its first request
clears the buffer, so replies from before the connection was made are ignored.

The Hub starts its buffer over for every command, so ``HubConnection`` reads the buffer just
before each write and keeps what it finds, rather than losing replies that arrived between
polls. A poll that fails, such as one that times out, is tried again at the next interval; the
connection gives up after ``HubConnection/defaultFailureLimit`` failures in a row, or at once
if the Hub answers with an error status such as `401`. Each request waits up to
``Hub/requestTimeout``, ``Hub/defaultRequestTimeout`` unless you pass another, so a Hub that
doesn't answer is reported in seconds.

A request that gets no answer fails with the HTTP client's error, such as a `URLError` whose
code is `timedOut`, while the Hub hasn't answered anything on the connection, as when its
address changed. Once the Hub has answered, such a request fails with ``HubStoppedAnswering``
instead: the Hub is reachable but busy, as when its modem is still sending a message to a
device that doesn't answer, so trying again is more useful than looking for the Hub.

``Hub`` is the HTTP interface underneath: writing bytes, reading the buffer and clearing it,
with no pacing or retries. Use it directly only to build something other than a
`ModemConnection` on top of the Hub.

### Credentials and networking

The Hub requires the user name and password printed on it. Store them securely, for example in
the keychain, rather than in source code. Requests go through `HTTPClient` from
InsteonNetworking, so you can supply your own HTTP stack or a stub in tests.

A Hub never redirects its own requests, so the default client, `URLSessionHTTPClient`,
refuses any redirect for a request carrying the Hub's credentials and throws
`HTTPClientError.redirectRefused`: the credentials reach only the Hub's address, never
another host a redirect names. An HTTP stack of your own must refuse redirects for these
requests too.

The default client is `URLSessionHTTPClient.localNetwork()`. Its session goes to the Hub
directly, never through a proxy, which would read the credentials, and keeps no cookies,
credentials or cache. On Linux, where the environment's proxy can't be turned off, it refuses
a request a proxy would carry with `HTTPClientError.proxyConfigured`; naming the Hub's address
in `no_proxy` sends it directly. Each request may take ``Hub/requestTimeout`` in all, however
slowly the Hub answers, and a page larger than ``Hub/maximumResponseSize`` isn't read. The
first time the Hub rejects the credentials with `401` or `403`, a ``HubConnection`` sends no
more requests.

``Hub`` sends the credentials to whatever address its endpoint names. A front end that takes
the address from a person should check it first: InsteonCore's `ModemSession.withHub` sends
them only to an IPv4 address in `10.0.0.0/8`, `172.16.0.0/12` or `192.168.0.0/16`.

### Reaching a Hub away from home

The Hub's interface is meant for the local network: it's plain HTTP, so its password and
every command cross the network unencrypted, and the Hub has no way to be reached securely
from outside. Insteon's apps reached Hubs away from home through Insteon's own cloud
services rather than the Hub's interface, and this library doesn't use those.

To reach a Hub away from home, bring the app onto the home network instead of exposing the
Hub: connect through a VPN or tunnel into the home network, such as WireGuard or a mesh VPN,
and use the Hub's local address as usual. Or run an always-on app at home, on a Mac or a
small server, that talks to the Hub locally and offers its own authenticated, encrypted
interface to your other devices. Don't forward the Hub's port through the router.

### Supported Hubs

The Hubs were sold under similar names, so they're identified here by model number.

| Model | Also known as | Support |
| --- | --- | --- |
| 2245 | Hub | Supported |
| 2242 | Hub | Expected to work: it serves the same local HTTP requests on the same port, though its buffer format hasn't been verified |
| 2243 | Hub Pro | Expected to work: it's built on the same foundations and answers Hub discovery, though it hasn't been verified. `InsteonHubPro` covers the requests only it has |

HouseLinc drove the Hub 2242 and Hub 2245 the same way, which suggests they share
their local interface; it didn't drive the Hub Pro 2243. A Hub's modem reports its model through
`SerialCommand.getModemInfo`: category `0x03` with subcategory `0x33` to `0x36` for the Hub 2245,
`0x2B` or `0x2E` to `0x32` for the Hub 2242, or `0x18`, `0x2C` or `0x2D` for the Hub Pro 2243.

### Timers the Hub runs

A Hub 2242 runs timers on its own, so they keep running with no app connected. It keeps them in
256 numbered slots, 16 pages of 16, one page per room. Each slot has a name, an on time and an
off time, the days of the week it runs, and the serial commands it sends to turn on and off.
Timers go in slots 1 through 239: slot 240 holds the Hub's unlock code, and the last page is the
thermostat room, which stays disabled.

``Hub/setCommands(_:for:)`` sets what a slot sends, and ``Hub/setTimer(_:for:)`` sets when.
Times are a time of day, sunrise or sunset. The Hub works out sunrise and sunset from a table of
times by month, and it keeps the time of day and day of the week, which
``Hub/setClock(to:on:)`` sets. ``Hub/slotStatuses(page:)`` reads each slot's device, group and
state, but not its times.

Some of the requests' fields have no known meaning, and the requests haven't been verified on a
Hub. The Hub 2245 runs timers too, but only through Insteon's cloud, never through its local
interface. The SmartLinc 2412N may accept the same requests.

## Topics

### Connecting

- ``HubConnection``
- ``HubEndpoint``
- ``HubError``
- ``HubStoppedAnswering``

### The Hub's HTTP interface

- ``Hub``
- ``HubShortCommand``
- ``HubBuffer``
- ``HubBufferCursor``

### Timers

- ``HubSlot``
- ``HubSlotName``
- ``HubSlotStatus``
- ``HubSlotFlags``
- ``HubSlotCommands``
- ``HubTimer``
- ``HubTimerTime``
- ``HubClockTime``
- ``HubWeekday``
- ``HubWeekdays``
