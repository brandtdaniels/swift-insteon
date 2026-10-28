/// An IPv4 subnet: an address and the mask that says which of its bits name the network.
///
/// ```swift
/// let subnet = IPv4Subnet(address: "192.168.1.20", prefixLength: 24)
/// print(subnet?.hosts.first)   // "Optional("192.168.1.1")"
/// print(subnet?.hosts.count)   // "Optional(254)"
/// ```
public struct IPv4Subnet: Hashable, Sendable {

  /// An address in the subnet, such as the address of the interface it was read from.
  public let address: UInt32

  /// The subnet mask, whose set bits name the network.
  public let mask: UInt32

  /// Creates a subnet from an address and a mask, both as 32-bit numbers in host byte order.
  ///
  /// - Parameters:
  ///   - address: An address in the subnet.
  ///   - mask: The subnet mask.
  public init(address: UInt32, mask: UInt32) {

    self.address = address
    self.mask = mask

  }

  /// Creates a subnet from an address in dotted-decimal notation and a prefix length.
  ///
  /// - Parameters:
  ///   - address: An address in the subnet, such as `"192.168.1.20"`.
  ///   - prefixLength: How many leading bits name the network, from 0 to 32.
  /// - Returns: `nil` if the address isn't four numbers from 0 to 255 separated by dots, or
  ///   the prefix length is outside 0 to 32.
  public init?(address: String, prefixLength: Int) {

    let parts = address.split(separator: ".", omittingEmptySubsequences: false)

    guard parts.count == 4, (0...32).contains(prefixLength) else {

      return nil

    }

    var value: UInt32 = 0

    for part in parts {

      guard part.allSatisfy(\.isASCII), let octet = UInt8(part) else {

        return nil

      }

      value = value << 8 | UInt32(octet)

    }

    self.init(address: value, mask: prefixLength == 0 ? 0 : UInt32.max << (32 - prefixLength))

  }

  /// How many leading bits name the network.
  public var prefixLength: Int {

    mask.leadingZeroBitCount == 0 ? (~mask).leadingZeroBitCount : 0

  }

  /// The subnet's host addresses in dotted-decimal notation, in order: every address except
  /// the network address and the broadcast address. Empty for a subnet of one or two
  /// addresses, which has no room for a separate host. A short prefix means a great many
  /// hosts, so check ``IPv4Subnet/prefixLength`` first.
  public var hosts: [String] {

    let network = address & mask
    let broadcast = network | ~mask

    // Subtracting can't overflow, since the broadcast address is never below the network's.
    guard broadcast - network > 1 else {

      return []

    }

    return (network + 1..<broadcast).map(Self.dottedDecimal)

  }

  /// An address in dotted-decimal notation, such as `"192.168.1.20"`.
  static func dottedDecimal(_ address: UInt32) -> String {

    [24, 16, 8, 0].map { String(address >> $0 & 0xFF) }.joined(separator: ".")

  }

}

extension IPv4Subnet: CustomStringConvertible {

  /// The subnet's network address and prefix length, such as `"192.168.1.0/24"`.
  public var description: String {

    "\(Self.dottedDecimal(address & mask))/\(prefixLength)"

  }

}
