# Identifying Devices

Find out what kind of device is on the network and what it can do.

## Overview

Every INSTEON device belongs to a device category (DevCat) and subcategory (SubCat), and runs a
particular firmware version. Devices report these themselves, so an app never needs to ask the
user what they installed.

### Asking a device who it is

Send ``StandardDirectCommand/idRequest`` and the device answers with a SET Button Pressed
broadcast, which ``SetButtonPressed`` reads. The same broadcast arrives when someone holds the
device's SET button to link it.

Devices that support ``StandardDirectCommand/productDataRequest`` answer it with an extended
message, which ``ProductData`` reads.

When the modem becomes a device's controller by linking, it reports the device's category and
subcategory in ``AllLinkingCompleted``. Only devices that predate the Product Data Response
report a firmware version there; newer devices send `0xFF`, which reads as `nil`.

### Finding out what a device can do

What a device can do depends on its product and its firmware version, because commands can
differ between firmware versions of the same product. That information belongs in one shared
product database rather than in each app.

``ProductDatabase`` is how this package reads such a database. Conform a type to it that reads
the database from wherever your app gets it, then look a device up by what it reported:

```swift
func capabilities(
  of identity: SetButtonPressed,
  in database: some ProductDatabase
) async throws -> (any DeviceCapabilities)? {
  try await database.capabilities(
    category: identity.category,
    subcategory: identity.subcategory,
    firmwareVersion: identity.firmwareVersion
  )
}

if let capabilities = try await capabilities(of: identity, in: database),
   capabilities.responds(to: StandardDirectCommand.beep) {
  try await modem.send(.sendStandardMessage(
    StandardMessage(to: identity.sender, command: StandardDirectCommand.beep)
  ))
}
```
