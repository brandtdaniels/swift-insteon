# InsteonHubDiscovery

Find Insteon Hubs on your local network, by asking the network itself or, if you choose, Insteon Connect.

- `HubDiscovery`: asks every address on the device's subnets for the Hub's buffer page on port 25105, without credentials, and reports those that answer as a Hub does
- `InsteonConnectLookup`: reads Insteon Connect's Get Info page, which lists the Hubs that reported to Insteon from your network in the past 24 hours, with their Insteon IDs
- `DiscoveredHub`: a Hub that was found, with the `HubEndpoint` to connect to with InsteonHubClient
- `LocalNetwork`, `InterfaceNetwork` and `IPv4Subnet`: the subnets to search, read from the device's network interfaces

Only subnets of at most 1,024 addresses are searched. On iOS, iPadOS, tvOS and visionOS, add `NSLocalNetworkUsageDescription` to your app's `Info.plist`.

See the DocC catalog in `Sources/InsteonHubDiscovery/InsteonHubDiscovery.docc` for the full documentation.
