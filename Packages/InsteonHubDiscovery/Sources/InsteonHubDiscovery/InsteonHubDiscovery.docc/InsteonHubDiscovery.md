# ``InsteonHubDiscovery``

Find INSTEON Hubs on the local network, without Insteon's servers.

## Overview

A Hub doesn't announce itself on the local network. Insteon's apps found Hubs through
Insteon's servers, which each Hub reported its local address to. ``HubDiscovery`` finds them
locally instead: it asks every address on the device's subnets for the Hub's buffer page on
port `25105`, without credentials, and reports each address that answers the way a Hub does,
with `401 Unauthorized` and a `Basic` challenge.

```swift
import InsteonHubClient
import InsteonHubDiscovery

let hubs = try await HubDiscovery().discover { hub in
  print("Found a Hub at", hub.endpoint.host)
}

if let hub = hubs.first {
  let connection = HubConnection(hub: Hub(endpoint: hub.endpoint, user: username, password: password))
}
```

Discovery finds where a Hub is, not how to sign in: the user name and password are printed
on the Hub.

### What discovery sends

Discovery sends one request to each address on subnets of at most 1,024 addresses, a few
dozen at a time, and nothing more to the Hubs it finds. Another web server on port `25105`
that asks for a password the same way would be reported too, so the result is where to try
connecting rather than a guarantee.

### Local network permission

On iOS, iPadOS, tvOS and visionOS, an app that reaches devices on the local network must say
why with `NSLocalNetworkUsageDescription` in its `Info.plist`. The user is asked to allow it
the first time discovery runs, and until they do, every probe fails as if no Hub were there.

## Topics

### Discovering Hubs

- ``HubDiscovery``
- ``DiscoveredHub``

### The local network

- ``LocalNetwork``
- ``InterfaceNetwork``
- ``IPv4Subnet``
- ``LocalNetworkError``
