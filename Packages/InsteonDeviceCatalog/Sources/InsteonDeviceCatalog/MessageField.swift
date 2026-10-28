import InsteonProtocol

/// A value a command set says a message carries: where it is, and how to read and write it.
///
/// A field in a standard message is cmd2. A field in an extended message is one or more user
/// data bytes, most significant first. A ``MessageField/mask`` picks out some bits of a
/// single byte, so two fields can share a byte, such as a thermostat's mode in the high four
/// bits and its fan setting in the low four.
public struct MessageField: Hashable, Sendable {

  /// The field's name.
  public var name: SettingName

  /// What the field is.
  public var summary: String

  /// Where the field is.
  public var location: FieldLocation

  /// The bits of the byte that hold the field, if not all of them. They should be contiguous.
  public var mask: UInt8?

  /// How to read the field.
  public var kind: FieldKind

  /// The values the field can take, in its unit, if the command set gives them.
  public var range: ClosedRange<Double>?

  /// Creates a field.
  ///
  /// - Parameters:
  ///   - name: The field's name.
  ///   - summary: What the field is.
  ///   - location: Where the field is.
  ///   - mask: The bits of the byte that hold the field, if not all of them.
  ///   - kind: How to read the field.
  ///   - range: The values the field can take, in its unit.
  public init(name: SettingName, summary: String, location: FieldLocation, mask: UInt8? = nil, kind: FieldKind = .number(), range: ClosedRange<Double>? = nil) {

    self.name = name
    self.summary = summary
    self.location = location
    self.mask = mask
    self.kind = kind
    self.range = range

  }

  /// Reads the field.
  ///
  /// - Parameters:
  ///   - command2: The message's cmd2.
  ///   - userData: The message's user data, if it's an extended message.
  /// - Returns: The field's value, or `nil` if it's in user data and there's none.
  public func value(command2: UInt8, userData: UserData?) -> FieldValue? {

    guard let bytes = bytes(command2: command2, userData: userData) else {

      return nil

    }

    var raw = bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }

    if let mask {

      raw = (raw & UInt64(mask)) >> mask.trailingZeroBitCount

    }

    switch kind {
    case let .number(isSigned, scale, _):
      let width = bitWidth(byteCount: bytes.count)
      var number = Int64(raw)

      if isSigned, raw >> (width - 1) & 1 == 1 {

        number -= Int64(1) << width

      }

      return .number(Double(number) * scale)
    case .buttons:
      return .buttons(Set((0..<bitWidth(byteCount: bytes.count)).filter { raw >> $0 & 1 == 1 }.map { $0 + 1 }))
    case let .enumeration(enumeration):
      return enumeration.name(for: UInt8(truncatingIfNeeded: raw)).map(FieldValue.named) ?? .unnamed(Int(raw))
    case let .flags(bits):
      return .flags(Set(bits.filter { UInt64($0.mask) & raw != 0 }.map(\.name)))
    case .boolean:
      return .boolean(raw != 0)
    }

  }

  /// The bytes the field fills, given what's in them already.
  ///
  /// Bits outside the field's ``MessageField/mask`` keep their value.
  ///
  /// - Parameters:
  ///   - value: The value to write.
  ///   - current: The bytes at the field's location, cmd2 or its user data bytes in order.
  /// - Returns: The bytes, in the same order.
  /// - Throws: ``FieldError`` if the value isn't of the field's kind, names something the
  ///   field doesn't have, or doesn't fit.
  public func encoded(_ value: FieldValue, over current: [UInt8]) throws(FieldError) -> [UInt8] {

    let raw = try rawValue(for: value, width: bitWidth(byteCount: current.count))

    if let mask, let byte = current.first {

      return [byte & ~mask | UInt8(truncatingIfNeeded: raw << mask.trailingZeroBitCount) & mask]

    }

    return (0..<current.count).reversed().map { UInt8(truncatingIfNeeded: raw >> ($0 * 8)) }

  }

  /// The user data bytes the field is in, or an empty list for cmd2.
  var positions: [Int] {

    if case let .userData(positions) = location {

      return positions

    }

    return []

  }

  private func bytes(command2: UInt8, userData: UserData?) -> [UInt8]? {

    switch location {
    case .command2:
      [command2]
    case let .userData(positions):
      userData.map { userData in positions.map { userData[$0] } }
    }

  }

  private func bitWidth(byteCount: Int) -> Int {

    mask.map { 8 - $0.leadingZeroBitCount - $0.trailingZeroBitCount } ?? byteCount * 8

  }

  private func rawValue(for value: FieldValue, width: Int) throws(FieldError) -> UInt64 {

    let limit = UInt64(1) << width

    switch (kind, value) {
    case let (.number(isSigned, scale, _), .number(number)):
      let counts = (number / scale).rounded()
      let lowest = isSigned ? -Double(limit / 2) : 0
      let highest = isSigned ? Double(limit / 2) - 1 : Double(limit) - 1

      guard range?.contains(number) ?? true, counts.isFinite, (lowest...highest).contains(counts) else {

        throw .outOfRange(name)

      }

      return UInt64(bitPattern: Int64(counts)) & (limit - 1)
    case let (.buttons, .buttons(buttons)):
      guard buttons.allSatisfy({ (1...width).contains($0) }) else {

        throw .outOfRange(name)

      }

      return buttons.reduce(0) { $0 | UInt64(1) << ($1 - 1) }
    case let (.enumeration(enumeration), .named(valueName)):
      guard let byte = enumeration.value(named: valueName) else {

        throw .unknownName(valueName)

      }

      return UInt64(byte)
    case let (.enumeration, .unnamed(number)), let (.number, .unnamed(number)):
      guard number >= 0, UInt64(number) < limit else {

        throw .outOfRange(name)

      }

      return UInt64(number)
    case let (.flags(bits), .flags(names)):
      var raw = UInt64(0)

      for bitName in names {

        guard let bit = bits.first(where: { $0.name == bitName }) else {

          throw .unknownName(bitName)

        }

        raw |= UInt64(bit.mask)

      }

      return raw
    case let (.boolean, .boolean(isOn)):
      return isOn ? 1 : 0
    default:
      throw .mismatchedKind(name)
    }

  }

}

/// Where a ``MessageField`` is in a message.
public enum FieldLocation: Hashable, Sendable {

  /// cmd2 of a standard message.
  case command2

  /// User data bytes of an extended message, from 1 through 14 for D1 through D14, most
  /// significant first.
  case userData([Int])

}

/// How to read a ``MessageField``.
public enum FieldKind: Hashable, Sendable {

  /// A number: the field's bits, as a two's complement number if `isSigned`, times `scale`,
  /// in `unit`.
  case number(isSigned: Bool = false, scale: Double = 1, unit: FieldUnit? = nil)

  /// One bit per button, button 1 in bit 0.
  case buttons

  /// A name for each value.
  case enumeration(FieldEnumeration)

  /// Named bits.
  case flags([FieldBit])

  /// True when nonzero.
  case boolean

}

/// The unit of a number in a ``MessageField``.
public enum FieldUnit: String, Hashable, Sendable {

  /// Percent.
  case percent

  /// Degrees Celsius.
  case celsius

  /// Degrees Fahrenheit.
  case fahrenheit

  /// Degrees in the scale the device displays. A command set's
  /// ``CommandSet/celsiusIndicator`` names what says which scale that is; until it's been
  /// read, or when the command set has none, they're Fahrenheit.
  case displayDegrees

  /// Seconds.
  case seconds

  /// Minutes.
  case minutes

  /// Hours.
  case hours

}

/// Names for the values of a field, such as a thermostat's modes.
public struct FieldEnumeration: Hashable, Sendable {

  /// One named value.
  public struct Entry: Hashable, Sendable {

    /// The value.
    public var value: UInt8

    /// Its name.
    public var name: SettingName

    /// Creates a named value.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - name: Its name.
    public init(value: UInt8, name: SettingName) {

      self.value = value
      self.name = name

    }

  }

  /// The enumeration's name.
  public var name: SettingName

  /// The named values.
  public var entries: [Entry]

  /// Creates an enumeration.
  ///
  /// - Parameters:
  ///   - name: The enumeration's name.
  ///   - entries: The named values.
  public init(name: SettingName, entries: [Entry]) {

    self.name = name
    self.entries = entries

  }

  /// The name of a value.
  ///
  /// - Parameter value: The value.
  /// - Returns: Its name, or `nil` if the enumeration doesn't name it.
  public func name(for value: UInt8) -> SettingName? {

    entries.first { $0.value == value }?.name

  }

  /// The value with a name.
  ///
  /// - Parameter name: The name.
  /// - Returns: The value, or `nil` if the enumeration has no such name.
  public func value(named name: SettingName) -> UInt8? {

    entries.first { $0.name == name }?.value

  }

}

/// A named bit of a field whose kind is ``FieldKind/flags(_:)``.
public struct FieldBit: Hashable, Sendable {

  /// The bit's mask.
  public var mask: UInt8

  /// What the bit means when it's 1.
  public var name: SettingName

  /// Creates a named bit.
  ///
  /// - Parameters:
  ///   - mask: The bit's mask.
  ///   - name: What the bit means when it's 1.
  public init(mask: UInt8, name: SettingName) {

    self.mask = mask
    self.name = name

  }

}

/// A field's value, read from a message or to be written into one.
public enum FieldValue: Hashable, Sendable {

  /// A number, in the field's unit.
  case number(Double)

  /// The buttons whose bits are set, numbered from 1.
  case buttons(Set<Int>)

  /// The name of an enumeration's value.
  case named(SettingName)

  /// A value an enumeration doesn't name.
  case unnamed(Int)

  /// The names of the bits that are set.
  case flags(Set<SettingName>)

  /// Whether the field is nonzero.
  case boolean(Bool)

}

/// Why a field couldn't be written.
public enum FieldError: Error, Hashable, Sendable {

  /// The value isn't the field's kind, such as a name for a number. The associated value is
  /// the field's name.
  case mismatchedKind(SettingName)

  /// The value is outside the field's range, or doesn't fit its bits. The associated value is
  /// the field's name.
  case outOfRange(SettingName)

  /// The name isn't one of the field's enumeration values or bits.
  case unknownName(SettingName)

  /// The command needs a value for this field, and none was given.
  case missingValue(SettingName)

}
