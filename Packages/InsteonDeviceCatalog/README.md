# InsteonDeviceCatalog

Find what an INSTEON device is and can do from the category, subcategory and firmware version it reports.

- `DeviceCatalog`: the profiles, a copy of the INSTEON device catalog shipped with the package, and lookups by identity or model
- `DeviceProfile`: a product's model, name, identities, ALL-Link groups and capabilities, what it means by each command it sends to a group, and its heartbeat interval
- `DeviceCatalogUpdater`: downloads the published catalog when it differs from the app's copy, checked against the manifest's SHA-256
- `DeviceEventInterpreter` and `DeviceEvent`: the messages a modem receives, read through each device's profile, such as a leak sensor's group 2 on as `wet`
- `DeviceCapability`, `DeviceIdentity`, `ProductModel` and `DeviceEventName`: the parts of a profile

The shipped copy is `Sources/InsteonDeviceCatalog/Resources/catalog.json`, the `v1/catalog.json` the [INSTEON device catalog](https://github.com/brandtdaniels/insteon-device-catalog) publishes. Refresh it with `Scripts/update-device-catalog.sh`.

See the DocC catalog in `Sources/InsteonDeviceCatalog/InsteonDeviceCatalog.docc` for the full documentation.
