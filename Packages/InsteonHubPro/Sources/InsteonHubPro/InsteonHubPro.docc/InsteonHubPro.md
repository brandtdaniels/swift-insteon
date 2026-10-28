# ``InsteonHubPro``

Add INSTEON devices to a Hub Pro, read its settings, and update its software.

## Overview

The Hub Pro (2243-222) is a HomeKit bridge for INSTEON devices. Once a device is added to
it, the Hub Pro shows the device as a HomeKit accessory, and apps control it through
HomeKit's standard services, such as a light bulb's power state and brightness. The Hub Pro
doesn't offer the buffer interface of the Hub models 2245 and 2242, so `InsteonHubClient`
doesn't work with it.

``HubProClient`` covers what HomeKit doesn't: its local HTTP interface adds and removes
INSTEON devices, reports the Hub Pro's network settings and software versions, and installs
software updates.

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

A Hub Pro is set up like any HomeKit accessory, with its setup code. In HomeKit its
accessory information reports the model `2243-222` and the manufacturer `Insteon`, and its
serial number is its INSTEON ID, such as `1A.2B.3C`. The accessories it bridges are the
INSTEON devices added to it.

The local interface needs the Hub Pro's IP address, which HomeKit doesn't give apps.
Insteon's app looked it up by INSTEON ID through Insteon's cloud service; the router's list
of clients shows it too.

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
