import InsteonDeviceCatalog

/// The rules that keep a device reachable and unlocked, shared with the catalog's own check of
/// a catalog loaded in place of the bundled copy, so the two never differ.
typealias DeviceSettingSafety = CommandSetSafety
