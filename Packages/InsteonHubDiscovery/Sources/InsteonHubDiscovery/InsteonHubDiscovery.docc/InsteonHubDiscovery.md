# ``InsteonHubDiscovery``

Find Insteon Hubs and Hub Pros on the local network, by asking the network itself, browsing Bonjour for a Hub Pro, or asking Insteon Connect or Insteon's staging service.

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
and it sends no credentials: its client is an `UnauthenticatedHTTPClient`, which can be made
only from a `URLSessionHTTPClient` and refuses any request that carries credentials. The
default client goes to each address directly rather than through a proxy, keeps nothing
between requests, and gives up on an address after ``HubDiscovery/probeTimeout`` in all.

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

The page lists each Hub's MAC address and public IP address, so the default client keeps
nothing on the device: no cache, cookies or credentials. It follows a redirect only to HTTPS on
Insteon Connect's own host, and sends a `User-Agent` that names this package rather than the
app.

```swift
let hubs = try await InsteonConnectLookup().hubs()
```

### Local network permission

On iOS, iPadOS, tvOS and visionOS, an app that reaches devices on the local network must say
why with `NSLocalNetworkUsageDescription` in its `Info.plist`. The user is asked to allow it
the first time discovery runs, and until they do, every probe fails as if no Hub were there.

### Confirming a found Hub

A found Hub is a candidate until it answers Get IM Info with the user name and password printed
on it. ``HubIdentifier`` asks for that, but sends the credentials only where a Hub on the local
network is: to a candidate at a private address on the Hub's port, as ``HubAddressPolicy``
decides, stopping at the first candidate that rejects them. The per-candidate decision to send them stays with the caller, so a
command-line tool can ask in a terminal and an app can show a prompt.

```swift
let results = try await HubIdentifier().identify(result.hubs) { candidate in
  await userAllows(candidate) ? credentials : nil
} onResult: { candidate, outcome in
  report(candidate, outcome)
}
```

## Topics

### Discovering Hubs

- ``HubFinder``
- ``HubDiscovery``
- ``InsteonConnectLookup``
- ``DiscoveredHub``
- ``HubKind``
- ``DiscoverySource``
- ``InsteonConnectError``

### Finding a Hub Pro

A Hub Pro doesn't answer on the Hub's port. ``HubDiscovery`` also asks each port it's given with
``HubDiscovery/hubProPorts`` for the Hub Pro's root, and only a host that answers `401` without a
`WWW-Authenticate` header is asked for its settings. A browser given as
``HubDiscovery/bonjour`` finds one first, through the HomeKit service it advertises.

- ``HubProbe``
- ``HubProProbe``
- ``BonjourBrowsing``
- ``BonjourService``
- ``NetworkBonjourBrowser``

### Confirming a Hub

- ``HubIdentifier``
- ``HubAddressPolicy``

### The local network

- ``LocalNetwork``
- ``InterfaceNetwork``
- ``IPv4Subnet``
- ``LocalNetworkError``
