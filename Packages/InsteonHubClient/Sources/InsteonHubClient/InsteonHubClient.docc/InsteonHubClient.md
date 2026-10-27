# ``InsteonHubClient``

Control INSTEON devices through an INSTEON Hub on your local network.

## Overview

An INSTEON Hub has a built-in INSTEON modem that it exposes through a local HTTP interface. ``Hub`` sends serial commands to that modem and reads back its replies.

```swift
import InsteonHubClient
import InsteonProtocol

let hub = Hub(
  endpoint: HubEndpoint(host: "192.168.1.20"),
  user: username,
  password: password
)

let lamp = InsteonAddress(0xAA, 0xBB, 0xCC)
try await hub.send(.sendStandardMessage(
  StandardMessage(to: lamp, command: StandardDirectCommand.on(level: 0xFF))
))
```

``Hub`` conforms to `SerialCommandSender`, so code that sends commands can depend on that
protocol and work with any modem connection.

### Reading replies

The Hub collects the modem's replies in a ring buffer. Poll it with ``Hub/readBuffer()`` and
use a ``HubBufferCursor`` to get only the bytes that arrived since the last read:

```swift
try await hub.clearBuffer()
var cursor = HubBufferCursor()

let received = cursor.advance(to: try await hub.readBuffer())
```

### Credentials and networking

The Hub requires the user name and password printed on it. Store them securely, for example in
the keychain, rather than in source code. Requests go through `HTTPClient` from
InsteonNetworking, so you can supply your own HTTP stack or a stub in tests.

### Supported Hubs

Both supported Hubs were sold as the INSTEON Hub, so they're identified here by model number.

| Model | Also known as | Support |
| --- | --- | --- |
| 2245 | Hub 2 | Supported |
| 2242 | Hub 1 | Supported: it serves the same local HTTP requests on the same port |
| 2243 | Hub Pro | Not supported: it's built around HomeKit and has no documented local modem interface |

## Topics

### Connecting

- ``Hub``
- ``HubEndpoint``
- ``HubError``

### Reading replies

- ``HubBuffer``
- ``HubBufferCursor``
