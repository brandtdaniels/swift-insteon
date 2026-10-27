/// A device's Product Data Response, its reply to ``StandardDirectCommand/productDataRequest``.
///
/// The response is an extended direct message (cmd1 `0x03`) whose user data carries:
///
/// | Byte | Contents |
/// | --- | --- |
/// | D1 | Reserved |
/// | D2–D4 | ``productKey`` |
/// | D5 | ``category`` |
/// | D6 | ``subcategory`` |
/// | D7–D8 | Reserved |
/// | D9–D14 | ``userDefined``, which some manufacturers use for the firmware version |
///
/// Devices without a product key don't answer the request; they identify themselves only
/// through ``SetButtonPressed``.
public struct ProductData: Hashable, Sendable {

  /// The device that sent the response.
  public var sender: InsteonAddress

  /// The device's INSTEON Product Key.
  public var productKey: InsteonProductKey

  /// The device's category.
  public var category: DeviceCategory

  /// The device's subcategory.
  public var subcategory: UInt8

  /// D9 through D14, whose meaning the device's manufacturer defines.
  public var userDefined: [UInt8]

  /// Creates product data.
  ///
  /// - Parameters:
  ///   - sender: The device that sent the response.
  ///   - productKey: The device's product key.
  ///   - category: The device's category.
  ///   - subcategory: The device's subcategory.
  ///   - userDefined: D9 through D14.
  public init(
    sender: InsteonAddress,
    productKey: InsteonProductKey,
    category: DeviceCategory,
    subcategory: UInt8,
    userDefined: [UInt8]
  ) {

    self.sender = sender
    self.productKey = productKey
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
      productKey: InsteonProductKey(data[2], data[3], data[4]),
      category: DeviceCategory(rawValue: data[5]),
      subcategory: data[6],
      userDefined: (9...14).map { data[$0] }
    )

  }

}
