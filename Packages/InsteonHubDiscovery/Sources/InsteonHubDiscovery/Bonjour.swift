import Foundation

/// A service a Bonjour browse found, with the text record it advertises.
public struct BonjourService: Hashable, Sendable {

  /// The service's instance name.
  public var name: String

  /// The service type, such as `_hap._tcp`.
  public var type: String

  /// The domain, such as `local.`.
  public var domain: String

  /// The port the service itself answers on, which isn't necessarily the port of any other
  /// interface the device has.
  public var port: Int

  /// The service's text record, by key.
  public var textRecord: [String: String]

  /// Creates a service.
  ///
  /// - Parameters:
  ///   - name: The instance name.
  ///   - type: The service type.
  ///   - domain: The domain. Defaults to `local.`.
  ///   - port: The service's port.
  ///   - textRecord: The text record. Defaults to none.
  public init(name: String, type: String, domain: String = "local.", port: Int, textRecord: [String: String] = [:]) {

    self.name = name
    self.type = type
    self.domain = domain
    self.port = port
    self.textRecord = textRecord

  }

  /// The model the service's `md` record names, such as `2243-222`, if it gives one.
  public var model: String? {

    textRecord.first { $0.key.lowercased() == "md" }?.value

  }

}

/// Browses Bonjour for services, a read of the local network that sends no request to any host
/// the browse lists.
public protocol BonjourBrowsing: Sendable {

  /// Lists the services of a type as they're found. The stream ends when the browse does, or
  /// when the caller stops reading it.
  ///
  /// - Parameter type: The service type, such as `_hap._tcp`.
  /// - Returns: The services found, each once as it appears.
  func browse(type: String) async -> AsyncStream<BonjourService>

  /// Finds the IPv4 address a service resolves to.
  ///
  /// - Parameter service: A service the browse listed.
  /// - Returns: The address, or `nil` if the service doesn't resolve to one.
  func resolveAddress(of service: BonjourService) async -> String?

}
