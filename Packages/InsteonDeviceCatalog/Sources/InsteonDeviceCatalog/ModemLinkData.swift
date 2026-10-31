import InsteonProtocol

/// What Data 1 through Data 3 hold in the ALL-Link database records a modem writes itself
/// when it links with Start ALL-Linking, so an app writing such a record by hand writes the
/// same bytes.
///
/// A modem's profile gives it in ``DeviceProfile/modemLinkData``:
///
/// ```swift
/// if let bytes = profile.modemLinkData?.controller {
///   let data = bytes.map { $0.byte(category: category, subcategory: subcategory, firmwareVersion: firmware) }
///   print(data)   // [0x01, the responder's subcategory, its firmware version]
/// }
/// ```
public struct ModemLinkData: Hashable, Sendable {

  /// The bytes of the records in which the modem is the controller. A byte the list leaves
  /// out isn't known.
  public var controller: [ModemLinkDataByte]

  /// The bytes of the records in which the modem is the responder. A byte the list leaves out
  /// isn't known.
  public var responder: [ModemLinkDataByte]

  /// Creates a modem's record data.
  ///
  /// - Parameters:
  ///   - controller: The bytes of the records in which the modem is the controller.
  ///   - responder: The bytes of the records in which the modem is the responder.
  public init(controller: [ModemLinkDataByte] = [], responder: [ModemLinkDataByte] = []) {

    self.controller = controller
    self.responder = responder

  }

}

/// What one data byte of a record a modem writes holds: a fixed value, or a byte of the
/// linked device's identity as the device reported it in ALL-Linking Completed.
public struct ModemLinkDataByte: Hashable, Sendable {

  /// A byte of the linked device's identity.
  public struct IdentityByte: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

    /// The byte as the catalog writes it, such as `"subcategory"`.
    public let rawValue: String

    /// Creates an identity byte from the catalog's name for it.
    ///
    /// - Parameter rawValue: The byte as the catalog writes it.
    public init(rawValue: String) {

      self.rawValue = rawValue

    }

    /// The linked device's category.
    public static let category = IdentityByte(rawValue: "category")

    /// The linked device's subcategory.
    public static let subcategory = IdentityByte(rawValue: "subcategory")

    /// The linked device's firmware version.
    public static let firmware = IdentityByte(rawValue: "firmware")

    /// The byte as the catalog writes it.
    public var description: String { rawValue }

  }

  /// Which data byte of the record it is, from 1 through 3.
  public var position: Int

  /// The byte's name, such as `"subcategory"`.
  public var name: SettingName

  /// What the byte holds. The catalog's JSON calls it `description`.
  public var summary: String

  /// The byte the modem writes, when it's always the same.
  public var value: UInt8?

  /// The byte of the linked device's identity the byte holds, when it holds one. One from a
  /// later version of the catalog keeps its name.
  public var identity: IdentityByte?

  /// How sure the catalog is of the byte.
  public var verification: Verification

  /// Creates a data byte.
  ///
  /// - Parameters:
  ///   - position: Which data byte of the record it is, from 1 through 3.
  ///   - name: The byte's name.
  ///   - summary: What the byte holds.
  ///   - value: The byte the modem writes, when it's always the same.
  ///   - identity: The byte of the linked device's identity the byte holds.
  ///   - verification: How sure the catalog is of the byte. Defaults to ``Verification/documented``.
  public init(
    position: Int,
    name: SettingName,
    summary: String,
    value: UInt8? = nil,
    identity: IdentityByte? = nil,
    verification: Verification = .documented
  ) {

    precondition((1...3).contains(position), "An ALL-Link database record's data bytes are Data 1 through Data 3.")

    self.position = position
    self.name = name
    self.summary = summary
    self.value = value
    self.identity = identity
    self.verification = verification

  }

  /// The byte the modem writes for a linked device.
  ///
  /// - Parameters:
  ///   - category: The linked device's category, as ALL-Linking Completed reports it.
  ///   - subcategory: The linked device's subcategory.
  ///   - firmwareVersion: The linked device's firmware version.
  /// - Returns: The fixed value, or the identity byte it copies, or `nil` if the catalog
  ///   doesn't say what the byte holds.
  public func byte(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion) -> UInt8? {

    if let value {

      return value

    }

    if identity == .category {

      return category.rawValue

    }

    if identity == .subcategory {

      return subcategory.rawValue

    }

    if identity == .firmware {

      return firmwareVersion.rawValue

    }

    return nil

  }

}

// MARK: - Decodable

extension ModemLinkData: Decodable {

  private enum CodingKeys: String, CodingKey {

    case controller
    case responder

  }

  /// Decodes a modem's record data from its `modem` capability's `linkData`.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the JSON isn't record data, or a byte can't be read.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.init(
      controller: try container.decodeIfPresent([ModemLinkDataByte].self, forKey: .controller) ?? [],
      responder: try container.decodeIfPresent([ModemLinkDataByte].self, forKey: .responder) ?? []
    )

  }

}

extension ModemLinkDataByte: Decodable {

  private enum CodingKeys: String, CodingKey {

    case byte
    case name
    case summary = "description"
    case value
    case identity
    case verification

  }

  /// Decodes a data byte from a modem's `linkData`.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the JSON isn't a data byte, it isn't Data 1 through Data 3,
  ///   or its value isn't written as `0x` and two hexadecimal digits.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)
    let position = try container.decode(Int.self, forKey: .byte)

    guard (1...3).contains(position) else {

      throw DecodingError.dataCorruptedError(forKey: .byte, in: container, debugDescription: "An ALL-Link database record's data bytes are Data 1 through Data 3.")

    }

    self.init(
      position: position,
      name: SettingName(rawValue: try container.decode(String.self, forKey: .name)),
      summary: try container.decode(String.self, forKey: .summary),
      value: try container.decodeIfPresent(ProfileByte.self, forKey: .value)?.value,
      identity: try container.decodeIfPresent(String.self, forKey: .identity).map(IdentityByte.init(rawValue:)),
      verification: try container.decodeIfPresent(Verification.self, forKey: .verification) ?? .documented
    )

  }

}
