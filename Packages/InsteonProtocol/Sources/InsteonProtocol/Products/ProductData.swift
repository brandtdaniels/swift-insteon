/// A device's Product Data Response, its reply to ``StandardDirectCommand/productDataRequest``.
///
/// The response is an extended direct message (cmd1 `0x03`) whose user data carries, in the
/// Insteon Developer's Guide:
///
/// | Byte | Contents |
/// | --- | --- |
/// | D1 | Reserved, `0x00` |
/// | D2–D4 | ``productKey``, most significant byte first |
/// | D5 | ``category`` |
/// | D6 | ``subcategory`` |
/// | D7–D8 | Reserved, `0xFF` |
/// | D9–D14 | ``userDefined``, which some manufacturers use for the firmware version |
///
/// Insteon's later command tables agree on D2 through D6 but give D1 as a group or button and
/// D7 as a version, so this type doesn't read D1, D7 or D8.
///
/// Not every device answers the request; every device identifies itself with
/// ``SetButtonPressed``.
public struct ProductData: Hashable, Sendable {

  /// The device that sent the response.
  public var sender: InsteonAddress

  /// The device's product key.
  public var productKey: ProductKey

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
  ///   - productKey: The device's product key.
  ///   - category: The device's category.
  ///   - subcategory: The device's subcategory.
  ///   - userDefined: D9 through D14.
  public init(
    sender: InsteonAddress,
    productKey: ProductKey,
    category: DeviceCategory,
    subcategory: DeviceSubcategory,
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
  /// - Returns: `nil` unless the message is an extended direct message with cmd1 `0x03` and
  ///   cmd2 `0x00`.
  public init?(_ message: ReceivedMessage) {

    guard
      message.flags.messageType == .direct,
      // cmd2 0x00 is product data; other values carry other responses, such as text.
      message.command == Command(command1: 0x03, command2: 0x00),
      let data = message.userData
    else {

      return nil

    }

    self.init(
      sender: message.sender,
      productKey: ProductKey(data[2], data[3], data[4]),
      category: DeviceCategory(rawValue: data[5]),
      subcategory: DeviceSubcategory(rawValue: data[6]),
      userDefined: (9...14).map { data[$0] }
    )

  }

}
