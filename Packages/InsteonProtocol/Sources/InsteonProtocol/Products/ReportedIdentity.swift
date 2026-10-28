extension ReceivedMessage {

  /// Whether the message is a standard-length broadcast, or another type, with a cmd1.
  func isStandardBroadcast(command1: UInt8, type: MessageFlags.MessageType = .broadcast) -> Bool {

    flags.messageType == type && !flags.isExtended && command.command1 == command1

  }

  /// The identity a device's broadcast carries in its To address: its category, subcategory
  /// and firmware version, with a firmware version of `0xFF` read as `nil`.
  var reportedIdentity: (category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) {

    (
      DeviceCategory(rawValue: destination.high),
      DeviceSubcategory(rawValue: destination.middle),
      destination.low == 0xFF ? nil : FirmwareVersion(rawValue: destination.low)
    )

  }

}
