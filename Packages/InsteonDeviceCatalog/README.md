# InsteonDeviceCatalog

Find what an Insteon device is and can do from the category, subcategory and firmware version it reports.

- `DeviceCatalog`: the profiles, a copy of the Insteon device catalog shipped with the package, lookups by identity or model, and search by model, name, alias or identity
- `DeviceProfile`: a product's model, name, aliases, description, identities, ALL-Link groups and capabilities, what it means by each command it sends to a group, its heartbeat interval, and the Insteon engine a device runs given the identity and firmware version it reports
- `DeviceLifecycle`: how to install a product, link it, wake it, reset it and take it out of service, as steps for an app to guide or do itself, with alternatives such as linking from a Hub
- `DeviceCatalogUpdater` and `DeviceCatalogVersion`: downloads the published catalog when it differs from the app's copy, only if its version has the same MAJOR.MINOR as the shipped copy, and checked against the manifest's SHA-256
- `DeviceEventInterpreter` and `DeviceEvent`: the messages a modem receives, read through each device's profile, such as a leak sensor's group 2 on as `wet`
- `CommandSet`: the settings and messages a family of products shares, in Insteon's own message types: operating flags, extended settings, other standard and extended direct commands such as a thermostat's setpoints, and the direct messages a device sends on its own such as a thermostat's reports
- `GroupType`, `LinkDataByte` and `ValueTable`: what a device's groups are, how to read their state, what they can be told to do, what Data 1 through Data 3 of their ALL-Link database records hold, and names for values such as ramp rates
- `MessageField` and `FieldValue`: where a value sits in a message and how to read and write it, as a scaled number, buttons, a named value, named bits or a boolean
- `DeviceCapability`, `DeviceIdentity`, `ProductModel` and `DeviceEventName`: the parts of a profile

The catalog isn't signed: a download's integrity rests on HTTPS to the expected host plus the manifest's SHA-256, which only shows that the catalog matches a manifest fetched from the same host. So `DeviceCatalogUpdater`'s default client follows a redirect only to HTTPS at the same host and port, deciding before each one (`DeviceCatalogUpdater.redirectPolicy`, `RedirectPolicy.sameOriginHTTPSOnly`). A redirect that leaves HTTPS, even for one step, or goes to another host fails the update, and the app keeps its copy. A client passed in its place should refuse redirects the same way.

The shipped copy is `Sources/InsteonDeviceCatalog/Resources/catalog.json` and its `manifest.json`, the `v0/catalog.json` and `v0/manifest.json` the [Insteon device catalog](https://github.com/brandtdaniels/insteon-device-catalog) publishes. The manifest gives the catalog's version; the package reads catalogs with the shipped copy's MAJOR.MINOR, since below 1.0 any MINOR can change the format. Refresh both with `Scripts/update-device-catalog.sh`, which warns when the MAJOR.MINOR changes.

See the DocC catalog in `Sources/InsteonDeviceCatalog/InsteonDeviceCatalog.docc` for the full documentation.
