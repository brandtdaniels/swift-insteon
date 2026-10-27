# ``InsteonHubClient``

Control INSTEON devices through an INSTEON Hub on your local network.

## Overview

An INSTEON Hub has a built-in INSTEON modem that it exposes through a local HTTP interface. ``HubConnection`` turns that interface into a `ModemConnection`, so a `Modem`
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
let modem = Modem(connection: HubConnection(hub: hub))

let lamp = InsteonAddress(0xAA, 0xBB, 0xCC)
try await modem.send(.sendStandardMessage(
  StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))
))
```

### How the Hub is polled

The Hub collects the modem's replies in a ring buffer rather than pushing them. ``HubConnection``
reads it every half second by default, using a ``HubBufferCursor`` to pick out only the bytes
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

### Supported Hubs

Both supported Hubs were sold as the INSTEON Hub, so they're identified here by model number.

| Model | Also known as | Support |
| --- | --- | --- |
| 2245 | Hub 2 | Supported |
| 2242 | Hub 1 | Expected to work: it serves the same local HTTP requests on the same port, though its buffer format hasn't been verified |
| 2243 | Hub Pro | Not supported: it's built around HomeKit and has no documented local modem interface |

## Topics

### Connecting

- ``HubConnection``
- ``HubEndpoint``
- ``HubError``

### The Hub's HTTP interface

- ``Hub``
- ``HubBuffer``
- ``HubBufferCursor``
