import InsteonProtocol

/// How an app writing operating flags treats a bit, so it never cuts a device off, locks it,
/// or changes the message form it accepts.
///
/// An operating flag carries one in ``OperatingFlag/writeGuard``, and a bit of an extended
/// command's flags parameter in ``FieldBit/writeGuard``. It holds for Set Operating Flags, for
/// a write to a value whose ``SettingValue/flagsQuery`` names the flag's query, and for an
/// extended command's flags parameter that holds the bit:
///
/// ```swift
/// if let flag = commands.operatingFlag(named: "radioOff"), flag.writeGuard == .keep {
///   print("Leave", flag.name, "as the device reported it")
/// }
/// ```
public struct FlagGuard: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

  /// The guard as the catalog writes it, such as `"keep"`.
  public let rawValue: String

  /// Creates a guard from the catalog's name for it.
  ///
  /// - Parameter rawValue: The guard as the catalog writes it.
  public init(rawValue: String) {

    self.rawValue = rawValue

  }

  /// A write leaves the bit as the device reported it, as for radio off, powerline off and
  /// checksum required.
  public static let keep = FlagGuard(rawValue: "keep")

  /// A write may clear the bit but never sets it, as for the programming lock.
  public static let neverSet = FlagGuard(rawValue: "neverSet")

  /// The guard as the catalog writes it.
  public var description: String { rawValue }

}

/// Whether an app may send a command a command set describes.
///
/// A flag command, standard command or extended command carries one in its `sendGuard`, such
/// as ``DeviceStandardCommand/sendGuard``, when it's a Set Operating Flags command (cmd1
/// `0x20`) that turns radio off, powerline off, checksum required or the programming lock on.
public struct CommandGuard: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

  /// The guard as the catalog writes it, such as `"never"`.
  public let rawValue: String

  /// Creates a guard from the catalog's name for it.
  ///
  /// - Parameter rawValue: The guard as the catalog writes it.
  public init(rawValue: String) {

    self.rawValue = rawValue

  }

  /// An app never sends the command.
  public static let never = CommandGuard(rawValue: "never")

  /// The guard as the catalog writes it.
  public var description: String { rawValue }

}

/// An operating flag that linking can change on its own, which a linking flow may read before
/// it links and set back afterward.
///
/// A command set's ``CommandSet/linkingChanges`` is an allowlist: a linking flow changes and
/// restores no other flag, and never one with a ``FlagGuard``.
public struct LinkingChange: Hashable, Sendable {

  /// The operating flag, in the command set's ``CommandSet/operatingFlags``.
  public var flag: SettingName

  /// How sure the catalog is that linking changes the flag.
  public var verification: Verification

  /// Creates a flag linking changes.
  ///
  /// - Parameters:
  ///   - flag: The operating flag.
  ///   - verification: How sure the catalog is that linking changes the flag. Defaults to
  ///     ``Verification/documented``.
  public init(flag: SettingName, verification: Verification = .documented) {

    self.flag = flag
    self.verification = verification

  }

}

extension CommandSet {

  /// The operating flags whose bits an extended settings value's byte holds: those with the
  /// Get Operating Flags query the value's ``SettingValue/flagsQuery`` names.
  ///
  /// Writing such a value writes every flag in its byte, so an app reads the byte first, and
  /// refuses a write that changes a bit whose flag is ``FlagGuard/keep`` or sets one whose
  /// flag is ``FlagGuard/neverSet``.
  ///
  /// - Parameter value: The value.
  /// - Returns: The flags, in the command set's order, or none if the value's byte isn't an
  ///   operating flags byte.
  public func flagsHeld(by value: SettingValue) -> [OperatingFlag] {

    guard let query = value.flagsQuery else {

      return []

    }

    return operatingFlags.filter { $0.query == query }

  }

}
