/// A Hub Pro's network settings and software versions, as its `/settings` request reports
/// them.
///
/// The values are kept as the Hub Pro reports them.
public struct HubProSettings: Hashable, Sendable, Decodable {

  /// The Hub Pro's network settings.
  public struct Network: Hashable, Sendable, Decodable {

    /// The Hub Pro's IP address.
    public var address: String

    /// The DNS server the Hub Pro uses.
    public var dns: String?

    /// The Hub Pro's gateway.
    public var gateway: String?

    /// The Hub Pro's subnet mask.
    public var mask: String?

    /// How the Hub Pro gets its address, such as by DHCP.
    public var mode: String?

    /// The port the Hub Pro reports in its network settings.
    public var port: Int?

    /// Creates network settings.
    ///
    /// - Parameters:
    ///   - address: The IP address.
    ///   - dns: The DNS server.
    ///   - gateway: The gateway.
    ///   - mask: The subnet mask.
    ///   - mode: How the address is assigned.
    ///   - port: The reported port.
    public init(address: String, dns: String? = nil, gateway: String? = nil, mask: String? = nil, mode: String? = nil, port: Int? = nil) {

      self.address = address
      self.dns = dns
      self.gateway = gateway
      self.mask = mask
      self.mode = mode
      self.port = port

    }

  }

  /// One of the Hub Pro's pieces of software: the version it runs, and the versions it can
  /// update or roll back to.
  public struct SoftwareVersion: Hashable, Sendable, Decodable {

    /// The version the Hub Pro runs.
    public var version: String

    /// The version an update would install, or `nil` or empty if there's none.
    public var update: String?

    /// The version a rollback would restore, if any.
    public var rollback: String?

    /// Whether an update is waiting to be installed.
    public var isUpdateAvailable: Bool {

      !(update ?? "").isEmpty

    }

    /// Creates a software version.
    ///
    /// - Parameters:
    ///   - version: The version running.
    ///   - update: The version an update would install.
    ///   - rollback: The version a rollback would restore.
    public init(version: String, update: String? = nil, rollback: String? = nil) {

      self.version = version
      self.update = update
      self.rollback = rollback

    }

  }

  /// The versions of the Hub Pro's two pieces of software.
  public struct Versions: Hashable, Sendable, Decodable {

    /// The Hub Pro's configuration.
    public var config: SoftwareVersion

    /// The Hub Pro's server.
    public var server: SoftwareVersion

    /// Creates the versions.
    ///
    /// - Parameters:
    ///   - config: The configuration's version.
    ///   - server: The server's version.
    public init(config: SoftwareVersion, server: SoftwareVersion) {

      self.config = config
      self.server = server

    }

  }

  /// The Hub Pro's time, as it reports it.
  public var time: String

  /// The Hub Pro's network settings.
  public var network: Network

  /// The versions of the Hub Pro's software.
  public var version: Versions

  /// Whether an update is waiting to be installed for either piece of software.
  public var isUpdateAvailable: Bool {

    version.config.isUpdateAvailable || version.server.isUpdateAvailable

  }

  /// Creates settings.
  ///
  /// - Parameters:
  ///   - time: The Hub Pro's time.
  ///   - network: The network settings.
  ///   - version: The software versions.
  public init(time: String, network: Network, version: Versions) {

    self.time = time
    self.network = network
    self.version = version

  }

}
