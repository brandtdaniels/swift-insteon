/// An X10 transmission: either a unit address or a command for a house code.
///
/// X10 devices are addressed in two steps: send the unit's address, then a command for its
/// house code.
///
/// ```swift
/// SerialCommand.sendX10(.unit(.a, .one))   // address A1
/// SerialCommand.sendX10(.command(.a, .on)) // turn it on
/// ```
public enum X10Code: Hashable, Sendable {

  /// Addresses a unit within a house code.
  case unit(X10HouseCode, X10UnitCode)

  /// Sends a command to the house code's addressed units.
  case command(X10HouseCode, X10Command)

  /// Decodes an X10 transmission from its two bytes.
  ///
  /// - Parameters:
  ///   - rawX10: The house code in the high nibble and the unit or command in the low nibble.
  ///   - flag: `0x80` for a command or `0x00` for a unit address. Only bit 7 is read.
  public init(rawX10: UInt8, flag: UInt8) {

    // Every 4-bit value is a house, unit and command code, so these lookups always succeed.
    let house = X10HouseCode(rawValue: rawX10 >> 4)!
    let low = rawX10 & 0x0F

    if flag & 0x80 != 0 {

      self = .command(house, X10Command(rawValue: low)!)

    } else {

      self = .unit(house, X10UnitCode(rawValue: low)!)

    }

  }

  /// The X10 byte: the house code in the high nibble and the unit or command in the low nibble.
  public var rawX10: UInt8 {

    switch self {
    case let .unit(house, unit):
      house.rawValue << 4 | unit.rawValue
    case let .command(house, command):
      house.rawValue << 4 | command.rawValue
    }

  }

  /// The X10 flag: `0x00` for a unit address and `0x80` for a command.
  public var flag: UInt8 {

    switch self {
    case .unit: 0x00
    case .command: 0x80
    }

  }

}

// MARK: - ByteEncodable

extension X10Code: ByteEncodable {

  /// The two bytes the modem expects: ``X10Code/rawX10`` then ``X10Code/flag``.
  public var bytes: [UInt8] {

    [rawX10, flag]

  }

}
