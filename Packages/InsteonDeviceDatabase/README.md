# InsteonDeviceDatabase

Find what an INSTEON device is and can do from the category, subcategory and firmware version it reports.

- `DeviceDatabase`: the profiles, a copy of the INSTEON device database shipped with the package, and lookups by identity or model
- `DeviceProfile`: a product's model, name, identities, ALL-Link groups and capabilities, what it means by each command it sends to a group, and its heartbeat interval
- `DeviceCapability`, `DeviceIdentity`, `ProductModel` and `DeviceEventName`: the parts of a profile

The shipped copy is `Sources/InsteonDeviceDatabase/Resources/database.json`, the `v1/database.json` the [INSTEON device database](https://github.com/brandtdaniels/insteon-device-database) publishes. Refresh it with `Scripts/update-device-database.sh`.

See the DocC catalog in `Sources/InsteonDeviceDatabase/InsteonDeviceDatabase.docc` for the full documentation.
