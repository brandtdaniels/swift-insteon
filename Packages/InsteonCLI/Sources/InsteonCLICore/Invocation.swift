import InsteonProtocol

/// What a person asked the `insteon` command to do: where to find the modem, whether to print
/// JSON, and the subcommand to run.
///
/// ```swift
/// let invocation = try Invocation.parse(["--hub", "192.168.1.20", "device", "1A.2B.3C", "on", "50%"])
/// invocation.subcommand   // .device(InsteonAddress(0x1A, 0x2B, 0x3C), .on(levelPercent: 50))
/// ```
public struct Invocation: Hashable, Sendable {

  /// The Hub given with `--hub`, as `HOST` or `HOST:PORT`, if any.
  public var hub: String?

  /// The path of the serial port given with `--serial`, if any.
  public var serialPath: String?

  /// The environment file given with `--env-file`, if any, read in place of the per-user
  /// ``EnvironmentFile``.
  public var envFilePath: String?

  /// Whether `--json` asked for JSON output.
  public var printsJSON: Bool

  /// The subcommand to run.
  public var subcommand: Subcommand

  /// Creates an invocation.
  ///
  /// - Parameters:
  ///   - hub: The Hub given with `--hub`, if any. Defaults to `nil`.
  ///   - serialPath: The path given with `--serial`, if any. Defaults to `nil`.
  ///   - envFilePath: The path given with `--env-file`, if any. Defaults to `nil`.
  ///   - printsJSON: Whether to print JSON. Defaults to `false`.
  ///   - subcommand: The subcommand to run.
  public init(
    hub: String? = nil,
    serialPath: String? = nil,
    envFilePath: String? = nil,
    printsJSON: Bool = false,
    subcommand: Subcommand
  ) {

    self.hub = hub
    self.serialPath = serialPath
    self.envFilePath = envFilePath
    self.printsJSON = printsJSON
    self.subcommand = subcommand

  }

}

/// A subcommand of the `insteon` command.
public enum Subcommand: Hashable, Sendable {

  /// Prints help: the overview, or a subcommand's help when `topic` names one.
  case help(topic: String?)

  /// Finds Hubs on the local network, by asking the network itself, Insteon Connect, or both.
  /// By default, only the local network is asked.
  case discover(DiscoverOptions)

  /// Asks the modem about itself with Get IM Info.
  case info

  /// Reads and lists the modem's ALL-Link database.
  case links

  /// Puts the modem into linking mode with Start ALL-Linking and waits for a device's SET
  /// button.
  case link(LinkOptions)

  /// Takes the modem out of linking mode with Cancel ALL-Linking.
  case cancelLinking

  /// Puts the modem into unlinking mode and waits for a device's SET button.
  case unlink(UnlinkOptions)

  /// Sends a device a command, or reads its ALL-Link database.
  case device(InsteonAddress, DeviceAction)

  /// Prints what the modem hears until interrupted.
  case watch(WatchOptions)

}

/// How `insteon discover` looks for Hubs.
public struct DiscoverOptions: Hashable, Sendable {

  /// Whether to ask every address on the local private subnets.
  public var searchesLocalNetwork: Bool

  /// Whether to ask Insteon Connect, which sees the network's public IP address.
  public var asksInsteonConnect: Bool

  /// Creates discovery options.
  ///
  /// - Parameters:
  ///   - searchesLocalNetwork: Whether to search the local network. Defaults to `true`.
  ///   - asksInsteonConnect: Whether to ask Insteon Connect. Defaults to `false`, so the
  ///     network's public IP address is shared only when asked.
  public init(searchesLocalNetwork: Bool = true, asksInsteonConnect: Bool = false) {

    self.searchesLocalNetwork = searchesLocalNetwork
    self.asksInsteonConnect = asksInsteonConnect

  }

}

/// The modem's role when it links with a device.
public enum LinkingRole: String, Hashable, Sendable, CaseIterable {

  /// The modem controls the device, which joins one of the modem's ALL-Link groups.
  case controller

  /// The modem responds to the device, joining one of the device's ALL-Link groups.
  case responder

  /// The modem controls the device or responds to it, whichever the device's SET button asks
  /// for.
  case either

}

/// How `insteon link` links a device.
public struct LinkOptions: Hashable, Sendable {

  /// The modem's ALL-Link group.
  public var group: AllLinkGroupNumber

  /// The modem's role in the link.
  public var role: LinkingRole

  /// How many seconds to wait for the SET button, or `nil` for the library's default.
  public var timeoutSeconds: Int?

  /// Creates linking options.
  ///
  /// - Parameters:
  ///   - group: The modem's ALL-Link group. Defaults to group 1.
  ///   - role: The modem's role. Defaults to ``LinkingRole/controller``.
  ///   - timeoutSeconds: How many seconds to wait, or `nil` for the library's default.
  ///     Defaults to `nil`.
  public init(group: AllLinkGroupNumber = 1, role: LinkingRole = .controller, timeoutSeconds: Int? = nil) {

    self.group = group
    self.role = role
    self.timeoutSeconds = timeoutSeconds

  }

}

/// How `insteon unlink` removes a link.
public struct UnlinkOptions: Hashable, Sendable {

  /// The modem's ALL-Link group in the link.
  public var group: AllLinkGroupNumber

  /// The modem's role in the link: ``LinkingRole/controller`` or ``LinkingRole/responder``.
  public var role: LinkingRole

  /// How many seconds to wait for the SET button, or `nil` for the library's default.
  public var timeoutSeconds: Int?

  /// Creates unlinking options.
  ///
  /// - Parameters:
  ///   - group: The modem's ALL-Link group. Defaults to group 1.
  ///   - role: The modem's role. Defaults to ``LinkingRole/controller``.
  ///   - timeoutSeconds: How many seconds to wait, or `nil` for the library's default.
  ///     Defaults to `nil`.
  public init(group: AllLinkGroupNumber = 1, role: LinkingRole = .controller, timeoutSeconds: Int? = nil) {

    self.group = group
    self.role = role
    self.timeoutSeconds = timeoutSeconds

  }

}

/// What `insteon device ADDRESS` does with the device.
public enum DeviceAction: Hashable, Sendable {

  /// Asks for the device's engine with Get Insteon Engine Version, its identity with ID
  /// Request, and its product data with Product Data Request.
  case id

  /// Checks that the device answers, with Ping.
  case ping

  /// Turns the device on with Light On, at a level from 0 to 100 percent, or fully on when
  /// `nil`.
  case on(levelPercent: Int?)

  /// Turns the device off with Light Off.
  case off

  /// Asks for the device's level with Light Status Request.
  case status

  /// Reads the device's ALL-Link database.
  case links

}

/// How `insteon watch` prints what the modem hears.
public struct WatchOptions: Hashable, Sendable {

  /// Whether to print every reply the modem sends as it is, as well as the events read from
  /// it.
  public var printsRawReplies: Bool

  /// Creates watch options.
  ///
  /// - Parameter printsRawReplies: Whether to print every reply as it is. Defaults to `false`.
  public init(printsRawReplies: Bool = false) {

    self.printsRawReplies = printsRawReplies

  }

}
