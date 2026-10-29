# ``InsteonHubDiscovery``

Find Insteon Hubs on the local network, by asking the network itself or Insteon Connect.

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

Discovery sends one request to each address on private subnets (`10.0.0.0/8`,
`172.16.0.0/12` and `192.168.0.0/16`) of at most 1,024 addresses, a few dozen at a time, and
nothing more to the Hubs it finds. It never searches a cellular, public or larger network,
and it sends no credentials: its client mustn't add any.

Any device on port `25105` that asks for a password the same way would be reported too, so a
result is a candidate rather than a verified Hub. The Hub's interface sends its password
unencrypted, so show the user the address and let them confirm it before connecting with
their credentials. Once connected, `SerialCommand.getModemInfo` reports the Hub's modem,
whose subcategory names its model.

### Asking Insteon Connect

Each Hub also reports its local address to Insteon's servers, and Insteon Connect's Get Info
page lists the Hubs that reported from the same public IP address within the past 24 hours.
``InsteonConnectLookup`` reads that page, the way Insteon's own apps found Hubs. It doesn't
probe the local network and it gives each Hub's Insteon ID, which tells several Hubs apart,
and its modem's category and subcategory, which name its model,
but it needs the internet, sends the network's public IP address to Insteon, and misses a
Hub that hasn't reported recently. It's opt-in: nothing in this library calls it for you.

```swift
let hubs = try await InsteonConnectLookup().hubs()
```

### Local network permission

On iOS, iPadOS, tvOS and visionOS, an app that reaches devices on the local network must say
why with `NSLocalNetworkUsageDescription` in its `Info.plist`. The user is asked to allow it
the first time discovery runs, and until they do, every probe fails as if no Hub were there.

## Topics

### Discovering Hubs

- ``HubDiscovery``
- ``InsteonConnectLookup``
- ``DiscoveredHub``
- ``InsteonConnectError``

### The local network

- ``LocalNetwork``
- ``InterfaceNetwork``
- ``IPv4Subnet``
- ``LocalNetworkError``
