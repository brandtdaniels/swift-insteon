# InsteonHubPro

Add Insteon devices to a Hub Pro (2243-222) and manage it through its local HTTP interface.

- `HubProClient`: adds and removes devices, reads the Hub Pro's settings, and starts its software update
- `HubProSettings`: the Hub Pro's network settings and software versions
- `HubProError`: what the Hub Pro reported when a request failed

The Hub Pro's modem is driven with `HubConnection` in InsteonHubClient, like the other Hubs; this library covers the requests only the Hub Pro has.

See the DocC catalog in `Sources/InsteonHubPro/InsteonHubPro.docc` for the full documentation.
