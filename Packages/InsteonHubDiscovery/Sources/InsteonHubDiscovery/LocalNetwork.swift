#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The subnets this device is on, which ``HubDiscovery`` searches for Hubs.
///
/// ``InterfaceNetwork`` reads them from the device's network interfaces. Tests can conform a
/// type that returns fixed subnets.
public protocol LocalNetwork: Sendable {

  /// The IPv4 subnets this device is on.
  ///
  /// - Returns: Each subnet once.
  /// - Throws: An error if the subnets can't be read.
  func subnets() throws -> [IPv4Subnet]

}

/// Errors reported by ``InterfaceNetwork``.
public enum LocalNetworkError: Error, Hashable, Sendable {

  /// The system couldn't list the network interfaces; the value is its error number.
  case interfacesUnavailable(Int32)

}

/// The IPv4 subnets of the device's network interfaces that are up, other than loopback.
public struct InterfaceNetwork: LocalNetwork {

  /// Creates a reader of the device's network interfaces.
  public init() {}

  /// The IPv4 subnets of the interfaces that are up, other than loopback, in address order.
  ///
  /// - Returns: Each subnet once.
  /// - Throws: ``LocalNetworkError/interfacesUnavailable(_:)`` if the system can't list the
  ///   interfaces.
  public func subnets() throws -> [IPv4Subnet] {

    var first: UnsafeMutablePointer<ifaddrs>?

    guard getifaddrs(&first) == 0 else {

      throw LocalNetworkError.interfacesUnavailable(errno)

    }

    defer { freeifaddrs(first) }

    var subnets: Set<IPv4Subnet> = []
    var next = first

    while let current = next {

      let interface = current.pointee
      next = interface.ifa_next

      let flags = Int32(bitPattern: interface.ifa_flags)

      guard
        flags & Int32(IFF_UP) != 0,
        flags & Int32(IFF_LOOPBACK) == 0,
        let address = interface.ifa_addr,
        let netmask = interface.ifa_netmask,
        address.pointee.sa_family == sa_family_t(AF_INET)
      else {

        continue

      }

      subnets.insert(IPv4Subnet(address: Self.ipv4(address), mask: Self.ipv4(netmask)))

    }

    return subnets.sorted { ($0.address, $0.mask) < ($1.address, $1.mask) }

  }

  /// The IPv4 address in a socket address, in host byte order.
  private static func ipv4(_ address: UnsafeMutablePointer<sockaddr>) -> UInt32 {

    address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }

  }

}
