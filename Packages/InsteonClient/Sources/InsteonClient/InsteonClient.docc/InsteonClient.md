# ``InsteonClient``

Reach the service the same way from the couch and from across town.

## Overview

A ``ClientConnection`` gives the calls a service offers, listing its devices and running a command on one,
over whichever path reaches it. It tries its paths in order and keeps the first that opens: a
``LocalHubPath`` for a Hub found on the local network, then the routes a pairing document lists,
a ``ServicePath`` to the service on a local address, and a transport's route, which a
``RouteOpening`` turns into an address on this device. The calls are the service's own roles,
`DeviceQuerying` and `DeviceCommanding`, so code written against them works on a connection or on
the service itself.

```swift
let pairing = try ClientPairing(decoding: scannedDocument)
let connection = ClientConnection(pairing: pairing, local: localPath, routeOpeners: [transportOpener], http: URLSessionHTTPClient())

let devices = try await connection.devices()
let receipt = try await connection.execute(ServiceCommand(address: lamp, action: .on))
```

A read that loses its path is asked again on a path found afresh. A command that may have reached a
device is never sent again: the connection says it was interrupted, and the caller reads the device's
status before deciding.

The connection holds no user interface and no device knowledge. Each interface parses input, calls it
and presents the answer.

## Topics

### Connecting

- ``ClientConnection``
- ``ClientPairing``
- ``HomeStore``
- ``SecretStore``
- ``InMemorySecretStore``

### Paths

- ``ConnectionPath``
- ``ConnectionCalls``
- ``LocalHubPath``
- ``ServicePath``
- ``RouteOpening``

### Failures

- ``ConnectionError``
- ``ConnectionPathError``
- ``PathFailure``
