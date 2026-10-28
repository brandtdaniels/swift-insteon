# ``InsteonHubPro``

Add INSTEON devices to a Hub Pro, read its settings, and update its software.

## Overview

The Hub Pro (2243-222) has an INSTEON modem like the other Hubs, but it was sold as a HomeKit
bridge, and how to reach its modem directly isn't documented, so `InsteonHubClient` doesn't
support it. Current versions of HomeKit no longer support it either.

``HubProClient`` uses the Hub Pro's local HTTP interface, which adds and removes INSTEON
devices, reports the Hub Pro's network settings and software versions, and installs software
updates.

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

The local interface needs the Hub Pro's IP address. Insteon's app looked it up by INSTEON ID
through Insteon's cloud service; the router's list of clients shows it too. The Hub Pro's
INSTEON ID is printed on it.

### What the local interface trusts

The local interface is plain HTTP without authentication, so anything on the network can add
or remove devices or start an update. Keep it on the local network and don't forward its
port.

## Topics

### Talking to a Hub Pro

- ``HubProClient``
- ``HubProError``

### Settings

- ``HubProSettings``
