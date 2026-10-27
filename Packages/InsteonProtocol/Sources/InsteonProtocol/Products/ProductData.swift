/// A device's Product Data Response, its reply to ``StandardDirectCommand/productDataRequest``.
///
/// The response is an extended direct message (cmd1 `0x03`) whose user data carries:
///
/// | Byte | Contents |
/// | --- | --- |
/// | D1–D4 | Reserved |
/// | D5 | ``category`` |
/// | D6 | ``subcategory`` |
/// | D7–D8 | Reserved |
/// | D9–D14 | ``userDefined``, which some manufacturers use for the firmware version |
///
/// Not every device answers the request; every device identifies itself with
/// ``SetButtonPressed``.
public struct ProductData: Hashable, Sendable {

  /// The device that sent the response.
  public var sender: InsteonAddress

  /// The device's category.
  public var category: DeviceCategory

  /// The device's subcategory.
  public var subcategory: DeviceSubcategory

  /// D9 through D14, whose meaning the device's manufacturer defines.
  public var userDefined: [UInt8]

  /// Creates product data.
  ///
  /// - Parameters:
  ///   - sender: The device that sent the response.
  ///   - category: The device's category.
  ///   - subcategory: The device's subcategory.
  ///   - userDefined: D9 through D14.
  public init(sender: InsteonAddress, category: DeviceCategory, subcategory: DeviceSubcategory, userDefined: [UInt8]) {

    self.sender = sender
    self.category = category
    self.subcategory = subcategory
    self.userDefined = userDefined

  }

  /// Reads a Product Data Response from a received message.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: `nil` unless the message is an extended direct message with cmd1 `0x03`.
  public init?(_ message: ReceivedMessage) {

    guard
      message.flags.messageType == .direct,
      message.command.command1 == 0x03,
      let data = message.userData
    else {

      return nil

    }

    self.init(
      sender: message.sender,
      category: DeviceCategory(rawValue: data[5]),
      subcategory: DeviceSubcategory(rawValue: data[6]),
      userDefined: (9...14).map { data[$0] }
    )

  }

}
