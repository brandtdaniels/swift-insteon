# InsteonHubPro

Add Insteon devices to a Hub Pro 2243 and manage it through its local HTTP interface.

- `HubProClient`: adds and removes devices, reads the Hub Pro's settings, and starts its software update
- `HubProSettings`: the Hub Pro's network settings and software versions
- `HubProError`: what the Hub Pro reported when a request failed
- `HubProTransport`: lists the Hub Pro's devices, reads their levels and descriptions, and runs the commands of `HubProCommand` on them, one request at a time, with a `POST` when a `GET` isn't allowed
- `HubProCommand`: the commands the transport sends, which name no key that changes a device's links

The Hub Pro's modem is driven with `HubConnection` in InsteonHubClient, like the other Hubs; this library covers the requests only the Hub Pro has.

`HubProTransport`, reading the settings and the commands StatusRequest, On and Off have been run against a Hub Pro, and InsteonCore's `HubProNetwork` uses it. Adding, removing and updating haven't been run against one, and nothing in the repository uses them.

See the DocC catalog in `Sources/InsteonHubPro/InsteonHubPro.docc` for the full documentation.
