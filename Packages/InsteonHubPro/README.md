# InsteonHubPro

Add INSTEON devices to a Hub Pro (2243-222) and manage it through its local HTTP interface.

- `HubProClient`: adds and removes devices, reads the Hub Pro's settings, and starts its software update
- `HubProSettings`: the Hub Pro's network settings and software versions
- `HubProError`: what the Hub Pro reported when a request failed

The Hub Pro is a HomeKit bridge, so the devices added to it are controlled through HomeKit.

See the DocC catalog in `Sources/InsteonHubPro/InsteonHubPro.docc` for the full documentation.
