/// A scheme for protecting an extended message's user data against corruption.
///
/// Newer (i2cs) INSTEON devices reject extended messages whose integrity bytes don't
/// match. Which scheme a device expects depends on the device and command; most use
/// ``ChecksumIntegrity``, and some newer devices use ``CRCIntegrity`` for certain commands. Conform your own
/// type to support another scheme.
public protocol UserDataIntegrity: Sendable {

  /// Returns `userData` with its integrity bytes set for `command`.
  ///
  /// - Parameters:
  ///   - userData: The user data to protect.
  ///   - command: The command the user data is sent with, which the integrity bytes cover.
  /// - Returns: The user data with its integrity bytes filled in.
  func seal(_ userData: UserData, for command: Command) -> UserData

}

/// Leaves user data unchanged, for devices and commands that don't check integrity.
public struct UnprotectedIntegrity: UserDataIntegrity {

  /// Creates the scheme.
  public init() {}

  /// Returns `userData` unchanged.
  ///
  /// - Parameters:
  ///   - userData: The user data.
  ///   - command: Unused.
  /// - Returns: `userData`.
  public func seal(_ userData: UserData, for command: Command) -> UserData {

    userData

  }

}

/// Stores a one-byte checksum in D14, as i2cs devices require.
///
/// The checksum is the two's complement of the low byte of the sum of cmd1, cmd2 and
/// D1 through D13, so that all 16 bytes sum to zero modulo 256.
public struct ChecksumIntegrity: UserDataIntegrity {

  /// Creates the scheme.
  public init() {}

  /// Returns `userData` with D14 set to the checksum.
  ///
  /// - Parameters:
  ///   - userData: The user data. D14 is overwritten.
  ///   - command: The command the checksum covers.
  /// - Returns: The user data with D14 set.
  public func seal(_ userData: UserData, for command: Command) -> UserData {

    let covered = command.bytes + userData.bytes.prefix(13)
    let sum = covered.reduce(UInt8(0), &+)

    var sealed = userData
    sealed[14] = 0 &- sum

    return sealed

  }

}

/// Stores a two-byte CRC in D13 and D14, as some newer devices require for certain commands.
///
/// The CRC covers cmd1, cmd2 and D1 through D12. D13 holds its high byte and D14 its low byte.
public struct CRCIntegrity: UserDataIntegrity {

  /// Creates the scheme.
  public init() {}

  /// Returns `userData` with D13 and D14 set to the CRC.
  ///
  /// - Parameters:
  ///   - userData: The user data. D13 and D14 are overwritten.
  ///   - command: The command the CRC covers.
  /// - Returns: The user data with D13 and D14 set.
  public func seal(_ userData: UserData, for command: Command) -> UserData {

    var crc: UInt16 = 0

    for var byte in command.bytes + userData.bytes.prefix(12) {

      for _ in 0..<8 {

        var bit = UInt16(byte & 0x01)

        for tap: UInt16 in [0x8000, 0x4000, 0x1000, 0x0008] where crc & tap != 0 {

          bit ^= 0x01

        }

        crc = crc << 1 | bit
        byte >>= 1

      }

    }

    var sealed = userData
    sealed[13] = UInt8(crc >> 8)
    sealed[14] = UInt8(crc & 0xFF)

    return sealed

  }

}

extension UserDataIntegrity where Self == UnprotectedIntegrity {

  /// Leaves user data unchanged.
  public static var unprotected: UnprotectedIntegrity { UnprotectedIntegrity() }

}

extension UserDataIntegrity where Self == ChecksumIntegrity {

  /// Stores a one-byte checksum in D14.
  public static var checksum: ChecksumIntegrity { ChecksumIntegrity() }

}

extension UserDataIntegrity where Self == CRCIntegrity {

  /// Stores a two-byte CRC in D13 and D14.
  public static var crc: CRCIntegrity { CRCIntegrity() }

}
