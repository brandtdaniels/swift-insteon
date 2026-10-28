import InsteonProtocol

/// How sure the catalog is of a value: whether an Insteon document gives it, the documents
/// disagree on it, it's inferred, or it's been confirmed on a device.
///
/// An app can warn before it sends a command, or trusts a value, that isn't
/// ``Verification/Status/documented`` or ``Verification/Status/observed``:
///
/// ```swift
/// if let command = commandSet.standardCommand(named: "beep"), !command.verification.isSettled {
///   print("Insteon's documents aren't sure of this command:", command.verification.note ?? "")
/// }
/// ```
public struct Verification: Hashable, Sendable {

  /// How the catalog knows a value.
  public struct Status: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

    /// The status as the catalog writes it, such as `"conflicting"`.
    public let rawValue: String

    /// Creates a status from the catalog's name for it.
    ///
    /// - Parameter rawValue: The status as the catalog writes it.
    public init(rawValue: String) {

      self.rawValue = rawValue

    }

    /// An Insteon document gives the value, and none of the catalog's sources disagree.
    public static let documented = Status(rawValue: "documented")

    /// No document states the value; it's read from an example, a similar product or how the
    /// product behaves.
    public static let inferred = Status(rawValue: "inferred")

    /// Insteon's documents disagree, and the value is the one the catalog uses.
    public static let conflicting = Status(rawValue: "conflicting")

    /// The value has been confirmed on a device.
    public static let observed = Status(rawValue: "observed")

    /// The status as the catalog writes it.
    public var description: String { rawValue }

  }

  /// How the catalog knows the value. A status from a later version of the catalog keeps its
  /// name.
  public var status: Status

  /// What the status rests on, such as what each document gives.
  public var note: String?

  /// For an observed value, the firmware versions it was confirmed on.
  public var firmware: [FirmwareVersion]

  /// Creates a verification.
  ///
  /// - Parameters:
  ///   - status: How the catalog knows the value.
  ///   - note: What the status rests on.
  ///   - firmware: For an observed value, the firmware versions it was confirmed on.
  public init(status: Status, note: String? = nil, firmware: [FirmwareVersion] = []) {

    self.status = status
    self.note = note
    self.firmware = firmware

  }

  /// A value an Insteon document gives, the catalog's default.
  public static let documented = Verification(status: .documented)

  /// Whether the value is documented or observed, rather than inferred, conflicting or of a
  /// status from a later version of the catalog.
  public var isSettled: Bool {

    status == .documented || status == .observed

  }

}

// MARK: - Decodable

extension Verification: Decodable {

  private enum CodingKeys: String, CodingKey {

    case status
    case note
    case firmware

  }

  /// Decodes a verification from the catalog's JSON.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the JSON isn't a verification, or a firmware version isn't
  ///   written as `0x` and two hexadecimal digits.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.init(
      status: Status(rawValue: try container.decode(String.self, forKey: .status)),
      note: try container.decodeIfPresent(String.self, forKey: .note),
      firmware: try (container.decodeIfPresent([ProfileByte].self, forKey: .firmware) ?? []).map { FirmwareVersion(rawValue: $0.value) }
    )

  }

}
