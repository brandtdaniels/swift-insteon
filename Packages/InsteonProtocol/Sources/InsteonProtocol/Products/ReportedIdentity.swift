/// What a device said it is: the category, subcategory and firmware version it reported.
///
/// Devices report their identity in the To address of a ``SetButtonPressed`` broadcast, which
/// they send when their SET button is held and in reply to ``StandardDirectCommand/idRequest``,
/// and of a ``Heartbeat`` or ``DeviceStatusChanged`` broadcast. A modem reports the identity of
/// a device it became the controller of in ``AllLinkingCompleted``, and its own in
/// ``ModemInfo``. The Insteon device catalog looks products up by these three values.
///
/// Name a device from an identity like this rather than from the data bytes of a modem's
/// ALL-Link records, which don't reliably hold it.
///
/// An identity encodes each byte as `0x` and two uppercase hexadecimal digits, leaving out a
/// firmware version the device didn't report:
///
/// ```json
/// { "category" : "0x02", "firmwareVersion" : "0x41", "subcategory" : "0x2A" }
/// ```
///
/// ```swift
/// if case let .messageReceived(message) = reply, let pressed = SetButtonPressed(message) {
///   let identity = ReportedIdentity(pressed)
///   print(identity.category, identity.subcategory)   // "0x02 0x2A"
/// }
/// ```
public struct ReportedIdentity: Hashable, Sendable {

  /// The device's category.
  public var category: DeviceCategory

  /// The device's subcategory.
  public var subcategory: DeviceSubcategory

  /// The device's firmware version, or `nil` if it didn't report one.
  public var firmwareVersion: FirmwareVersion?

  /// Creates an identity.
  ///
  /// - Parameters:
  ///   - category: The device's category.
  ///   - subcategory: The device's subcategory.
  ///   - firmwareVersion: The device's firmware version, if it reported one.
  public init(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) {

    self.category = category
    self.subcategory = subcategory
    self.firmwareVersion = firmwareVersion

  }

  /// The identity in a SET Button Pressed broadcast, such as a device's answer to ID Request.
  ///
  /// - Parameter pressed: The broadcast.
  public init(_ pressed: SetButtonPressed) {

    self.init(category: pressed.category, subcategory: pressed.subcategory, firmwareVersion: pressed.firmwareVersion)

  }

  /// The identity the modem reported for a new link, which it does only when it became the
  /// controller.
  ///
  /// - Parameter link: The modem's report.
  /// - Returns: `nil` if the report has no category or subcategory.
  public init?(_ link: AllLinkingCompleted) {

    guard let category = link.category, let subcategory = link.subcategory else {

      return nil

    }

    self.init(category: category, subcategory: subcategory, firmwareVersion: link.firmwareVersion)

  }

  /// The identity in a heartbeat broadcast.
  ///
  /// - Parameter heartbeat: The broadcast.
  public init(_ heartbeat: Heartbeat) {

    self.init(category: heartbeat.category, subcategory: heartbeat.subcategory, firmwareVersion: heartbeat.firmwareVersion)

  }

  /// The identity in a device status changed broadcast.
  ///
  /// - Parameter status: The broadcast.
  public init(_ status: DeviceStatusChanged) {

    self.init(category: status.category, subcategory: status.subcategory, firmwareVersion: status.firmwareVersion)

  }

  /// The identity a modem reported for itself in reply to Get IM Info.
  ///
  /// - Parameter info: The modem's reply.
  public init(_ info: ModemInfo) {

    self.init(category: info.category, subcategory: info.subcategory, firmwareVersion: info.firmwareVersion)

  }

}

// MARK: - Codable

extension ReportedIdentity: Codable {

  private enum CodingKeys: String, CodingKey {

    case category
    case subcategory
    case firmwareVersion

  }

  /// Decodes an identity whose bytes are written as `0x` and two hexadecimal digits.
  ///
  /// - Parameter decoder: The decoder.
  /// - Throws: `DecodingError` if the category or subcategory is missing, or a byte isn't
  ///   written as `0x` and two hexadecimal digits.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)
    let categoryText: String = try container.decode(String.self, forKey: .category)
    let subcategoryText: String = try container.decode(String.self, forKey: .subcategory)
    let category: UInt8 = try Self.byte(categoryText, key: .category, in: container)
    let subcategory: UInt8 = try Self.byte(subcategoryText, key: .subcategory, in: container)
    var firmwareVersion: FirmwareVersion?

    if let text = try container.decodeIfPresent(String.self, forKey: .firmwareVersion) {

      let version: UInt8 = try Self.byte(text, key: .firmwareVersion, in: container)
      firmwareVersion = FirmwareVersion(rawValue: version)

    }

    self.init(
      category: DeviceCategory(rawValue: category),
      subcategory: DeviceSubcategory(rawValue: subcategory),
      firmwareVersion: firmwareVersion
    )

  }

  /// Encodes the identity's bytes as `0x` and two uppercase hexadecimal digits, leaving out a
  /// firmware version the device didn't report.
  ///
  /// - Parameter encoder: The encoder.
  /// - Throws: An error from the encoder.
  public func encode(to encoder: any Encoder) throws {

    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(category.description, forKey: .category)
    try container.encode(subcategory.description, forKey: .subcategory)
    try container.encodeIfPresent(firmwareVersion?.description, forKey: .firmwareVersion)

  }

  /// Reads a byte written as `0x` and two hexadecimal digits, throwing for the key if it isn't
  /// one.
  private static func byte(_ text: String, key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>) throws -> UInt8 {

    guard let value = parseByte(text) else {

      throw DecodingError.dataCorruptedError(
        forKey: key,
        in: container,
        debugDescription: "Expected 0x and two hexadecimal digits, such as 0x2A."
      )

    }

    return value

  }

  /// A byte written as `0x` and two hexadecimal digits, or `nil` if the text isn't one.
  ///
  /// - Parameter text: The text, such as `"0x2A"`.
  /// - Returns: The byte.
  private static func parseByte(_ text: String) -> UInt8? {

    guard text.count == 4, text.hasPrefix("0x") else {

      return nil

    }

    let digits: Substring = text.dropFirst(2)

    guard digits.allSatisfy(\.isHexDigit) else {

      return nil

    }

    return UInt8(digits, radix: 16)

  }

}

// MARK: - Reading identities from broadcasts

extension ReceivedMessage {

  /// Whether the message is a standard-length broadcast, or another type, with a cmd1.
  func isStandardBroadcast(command1: UInt8, type: MessageFlags.MessageType = .broadcast) -> Bool {

    flags.messageType == type && !flags.isExtended && command.command1 == command1

  }

  /// The identity a device's broadcast carries in its To address: its category, subcategory
  /// and firmware version, with a firmware version of `0xFF` read as `nil`.
  var reportedIdentity: ReportedIdentity {

    ReportedIdentity(
      category: DeviceCategory(rawValue: destination.high),
      subcategory: DeviceSubcategory(rawValue: destination.middle),
      firmwareVersion: destination.low == 0xFF ? nil : FirmwareVersion(rawValue: destination.low)
    )

  }

}
