# ``InsteonHubPro``

Add Insteon devices to a Hub Pro, read its settings, and update its software.

## Overview

The Hub Pro 2243 is built on the same foundations as the other Hubs, with an Insteon
modem that `HubConnection` in `InsteonHubClient` drives the same way. It was also sold as a
HomeKit bridge, a role HomeKit has since dropped.

``HubProClient`` covers the requests only the Hub Pro has, which Insteon's app used alongside
HomeKit: it adds and removes Insteon devices from the bridge, reports the Hub Pro's network
settings and software versions, and installs software updates.

```swift
import InsteonHubPro
import InsteonProtocol

let hubPro = HubProClient(host: "192.168.1.20")

try await hubPro.addDevice(InsteonAddress(0x1A, 0x2B, 0x3C))

if try await hubPro.settings().isUpdateAvailable {
  try await hubPro.startUpdate()
}
```

### Finding a Hub Pro

The Hub Pro answers Hub discovery like the other Hubs, so `HubDiscovery` in
`InsteonHubDiscovery` finds its address.

### What the local interface trusts

These requests are plain HTTP without authentication, so anything on the network can add or
remove devices or start an update. Keep it on the local network and don't forward its
port.

## Topics

### Talking to a Hub Pro

- ``HubProClient``
- ``HubProError``

### Settings

- ``HubProSettings``
