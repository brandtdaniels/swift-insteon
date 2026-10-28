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

  // Returns once the lamp's acknowledgement shows up in the Hub's buffer.
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
if the Hub answers with an error status such as `401`.

``Hub`` is the HTTP interface underneath: writing bytes, reading the buffer and clearing it,
with no pacing or retries. Use it directly only to build something other than a
`ModemConnection` on top of the Hub.

### Credentials and networking

The Hub requires the user name and password printed on it. Store them securely, for example in
the keychain, rather than in source code. Requests go through `HTTPClient` from
InsteonNetworking, so you can supply your own HTTP stack or a stub in tests.

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

HouseLinc drove the 2242 and 2245 the same way, which suggests they share
their local interface; it didn't drive the 2243. A Hub's modem reports its model through
`SerialCommand.getModemInfo`: category `0x03` with subcategory `0x33` to `0x36` for the 2245,
`0x2B` or `0x2E` to `0x32` for the 2242, or `0x18`, `0x2C` or `0x2D` for the 2243.

### Timers the Hub runs

A 2242 Hub runs timers on its own, so they keep running with no app connected. It keeps them in
256 numbered slots, 16 pages of 16, one page per room. Each slot has a name, an on time and an
off time, the days of the week it runs, and the serial commands it sends to turn on and off.
Timers go in slots 1 through 239, the ones Insteon's Hub app used: slot 240 holds the Hub's unlock
code, and the last page is the thermostat room, which the app kept disabled.

``Hub/setCommands(_:for:)`` sets what a slot sends, and ``Hub/setTimer(_:for:)`` sets when.
Times are a time of day, sunrise or sunset. The Hub works out sunrise and sunset from a table of
times by month, and it keeps the time of day and day of the week, which
``Hub/setClock(to:on:)`` sets. ``Hub/slotStatuses(page:)`` reads each slot's device, group and
state, but not its times.

These requests follow the ones Insteon's Hub app sent to the 2242, including fields whose
meaning the app doesn't give. They haven't been verified on a Hub. The 2245 Hub runs timers too,
but Insteon's app wrote them only through Insteon's cloud, never through the Hub's local
interface. Insteon's Hub app grew out of its SmartLinc app, so the SmartLinc 2412N may accept
the same requests.

## Topics

### Connecting

- ``HubConnection``
- ``HubEndpoint``
- ``HubError``

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
