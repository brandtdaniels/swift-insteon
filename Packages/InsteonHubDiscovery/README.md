# InsteonHubDiscovery

Find INSTEON Hubs on your local network, without Insteon's servers.

- `HubDiscovery`: asks every address on the device's subnets for the Hub's buffer page on port 25105, without credentials, and reports those that answer as a Hub does
- `DiscoveredHub`: a Hub that was found, with the `HubEndpoint` to connect to with InsteonHubClient
- `LocalNetwork`, `InterfaceNetwork` and `IPv4Subnet`: the subnets to search, read from the device's network interfaces

Only subnets of at most 1,024 addresses are searched. On iOS, iPadOS, tvOS and visionOS, add `NSLocalNetworkUsageDescription` to your app's `Info.plist`.

See the DocC catalog in `Sources/InsteonHubDiscovery/InsteonHubDiscovery.docc` for the full documentation.
