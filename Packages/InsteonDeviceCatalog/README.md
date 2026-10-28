# InsteonDeviceCatalog

Find what an Insteon device is and can do from the category, subcategory and firmware version it reports.

- `DeviceCatalog`: the profiles, a copy of the Insteon device catalog shipped with the package, lookups by identity or model, and search by model, name, alias or identity
- `DeviceProfile`: a product's model, name, aliases, description, identities, ALL-Link groups and capabilities, what it means by each command it sends to a group, its heartbeat interval, and the Insteon engine a device runs given the identity and firmware version it reports
- `DeviceCatalogUpdater`: downloads the published catalog when it differs from the app's copy, checked against the manifest's SHA-256
- `DeviceEventInterpreter` and `DeviceEvent`: the messages a modem receives, read through each device's profile, such as a leak sensor's group 2 on as `wet`
- `DeviceCapability`, `DeviceIdentity`, `ProductModel` and `DeviceEventName`: the parts of a profile

The shipped copy is `Sources/InsteonDeviceCatalog/Resources/catalog.json`, the `v1/catalog.json` the [Insteon device catalog](https://github.com/brandtdaniels/insteon-device-catalog) publishes. Refresh it with `Scripts/update-device-catalog.sh`.

See the DocC catalog in `Sources/InsteonDeviceCatalog/InsteonDeviceCatalog.docc` for the full documentation.
