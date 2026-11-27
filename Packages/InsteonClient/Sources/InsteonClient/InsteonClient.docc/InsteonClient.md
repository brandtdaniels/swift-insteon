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

Events come from ``ClientConnection/events()`` and ``ClientConnection/sequencedEvents(after:)``. They
follow the service's server-sent events through a ``ServicePath``, and when the path is lost the
connection waits, reaches a path again and resumes after the last cursor it saw. A
``ClientEvent/refresh(_:)`` says the service can't replay what was missed, so the client reads
everything it shows afresh.

```swift
for try await event in connection.events() {
  switch event {
  case .event(let event): show(event)
  case .refresh: try await reload()
  }
}
```

Scenes come from ``ClientConnection/scenes()``, which lists them from the ALL-Link databases the
service holds, and ``ClientConnection/refreshScenes()``, which has the service read them from the
hardware. A ``SceneList`` is whole only when every database was read and every record has its other
half, and says which devices it could not read and why. ``ClientConnection/runScene(_:action:idempotencyKey:)``
sends a scene's group Light On or Light Off once. The call carries an idempotency key, so a caller
that lost the answer asks again with the same key and the service sends nothing twice.

```swift
let list = try await connection.refreshScenes()
if let scene = list.scenes.first(where: \.isWritable) {
  let receipt = try await connection.runScene(scene.number, action: .on)
}
```

The connection holds no user interface and no device knowledge. Each interface parses input, calls it
and presents the answer.

## Topics

### Connecting

- ``ClientConnection``
- ``ClientPairing``
- ``PairingStore``
- ``SecretStore``
- ``InMemorySecretStore``

### Paths

- ``ConnectionPath``
- ``ConnectionCalls``
- ``LocalHubPath``
- ``ServicePath``
- ``RouteOpening``

### Scenes

- ``SceneList``
- ``SceneAction``
- ``SceneRunReceipt``

### Events

- ``ConnectionEvents``
- ``ClientEvents``
- ``ClientEvent``

### Failures

- ``ConnectionError``
- ``ConnectionPathError``
- ``PathFailure``
