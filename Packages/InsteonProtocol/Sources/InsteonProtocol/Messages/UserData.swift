/// The 14 bytes of user data, D1 through D14, carried by an extended-length message.
///
/// User data starts as all zeros. Set individual bytes by their 1-based position, as the
/// Insteon documentation numbers them:
///
/// ```swift
/// var userData = UserData()
/// userData[1] = 0x01  // D1
/// ```
public struct UserData: Hashable, Sendable {

  /// The number of user data bytes in an extended message.
  public static let count = 14

  /// The user data bytes, D1 first. Always contains ``UserData/count`` bytes.
  public private(set) var bytes: [UInt8]

  /// Creates user data with every byte set to zero.
  public init() {

    bytes = Array(repeating: 0x00, count: Self.count)

  }

  /// Creates user data from leading bytes, padding the rest with zeros.
  ///
  /// - Parameter bytes: Up to 14 bytes, starting with D1.
  /// - Throws: ``UserDataError/tooManyBytes(_:)`` if more than 14 bytes are given.
  public init(_ bytes: [UInt8]) throws(UserDataError) {

    guard bytes.count <= Self.count else {

      throw .tooManyBytes(bytes.count)

    }

    self.bytes = bytes + Array(repeating: 0x00, count: Self.count - bytes.count)

  }

  /// Accesses a byte by its 1-based position, D1 through D14.
  ///
  /// - Parameter position: A position from 1 through 14.
  /// - Precondition: `position` is in `1...14`.
  public subscript(position: Int) -> UInt8 {

    get {

      precondition((1...Self.count).contains(position), "User data positions are 1 through \(Self.count)")

      return bytes[position - 1]

    }

    set {

      precondition((1...Self.count).contains(position), "User data positions are 1 through \(Self.count)")

      bytes[position - 1] = newValue

    }

  }

}

// MARK: - ByteEncodable

extension UserData: ByteEncodable {}

/// Errors creating ``UserData``.
public enum UserDataError: Error, Hashable, Sendable {

  /// More than 14 bytes were given. The associated value is the number given.
  case tooManyBytes(Int)

}
