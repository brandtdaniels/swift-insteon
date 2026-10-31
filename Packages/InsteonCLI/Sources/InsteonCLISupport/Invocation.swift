import InsteonCore

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
  case links(LinksOptions)

  /// Links a device to the modem: by its address, with Enter Linking Mode, or with its SET
  /// button.
  case link(LinkOptions)

  /// Takes the modem out of linking mode with Cancel ALL-Linking.
  case cancelLinking

  /// Puts the modem into unlinking mode and waits for a device's SET button.
  case unlink(UnlinkOptions)

  /// Removes a device from the network: every link between it and the modem, then what the
  /// identity cache keeps about it, and shows the catalog's factory reset steps.
  case remove(RemoveOptions)

  /// Sends a device a command, or reads its ALL-Link database.
  case device(InsteonAddress, DeviceAction)

  /// Prints what the modem hears until interrupted.
  case watch(WatchOptions)

  /// Makes the modem beep with Beep, twice when `isDouble`.
  case beep(isDouble: Bool)

  /// Sends a command to one of the modem's ALL-Link groups with Send ALL-Link Command.
  case scene(group: AllLinkGroupNumber, isOn: Bool)

  /// Writes a serial command to the modem as given and prints what it sends back, for
  /// exploring.
  case modemSend(RawSerialRequest)

  /// Prints the versions of the bundled and cached copies of the Insteon device catalog, and
  /// which one is in use. Needs no modem.
  case catalog

  /// Downloads the published Insteon device catalog into the cache directory when it's newer
  /// than the copy in use. Needs no modem, and reads no Hub settings.
  case catalogUpdate

}

/// A serial command for `insteon modem send` to write as given.
public struct RawSerialRequest: Hashable, Sendable {

  /// The command's bytes, starting with `0x02`.
  public var bytes: [UInt8]

  /// How many seconds to print what the modem sends back.
  public var waitSeconds: Int

  /// Creates a request.
  ///
  /// - Parameters:
  ///   - bytes: The command's bytes, starting with `0x02`.
  ///   - waitSeconds: How many seconds to print what the modem sends back. Defaults to 3.
  public init(bytes: [UInt8], waitSeconds: Int = 3) {

    self.bytes = bytes
    self.waitSeconds = waitSeconds

  }

}

/// A direct message for `insteon device ADDRESS send` to send as given.
public struct DirectMessageRequest: Hashable, Sendable {

  /// The message's cmd1.
  public var command1: UInt8

  /// The message's cmd2.
  public var command2: UInt8

  /// D1 onward for an extended message, the rest `0x00`, or `nil` for a standard message.
  public var userData: [UInt8]?

  /// Whether to put a checksum in D14, as i2CS devices require.
  public var hasChecksum: Bool

  /// How many seconds to print the device's messages after its acknowledgment.
  public var waitSeconds: Int

  /// Creates a request.
  ///
  /// - Parameters:
  ///   - command1: The message's cmd1.
  ///   - command2: The message's cmd2.
  ///   - userData: D1 onward for an extended message, or `nil` for a standard one. Defaults
  ///     to `nil`.
  ///   - hasChecksum: Whether to put a checksum in D14. Defaults to `true`.
  ///   - waitSeconds: How many seconds to print the device's messages. Defaults to 3.
  public init(command1: UInt8, command2: UInt8, userData: [UInt8]? = nil, hasChecksum: Bool = true, waitSeconds: Int = 3) {

    self.command1 = command1
    self.command2 = command2
    self.userData = userData
    self.hasChecksum = hasChecksum
    self.waitSeconds = waitSeconds

  }

}

/// A setting for `insteon device ADDRESS set` to change.
public struct SettingRequest: Hashable, Sendable {

  /// The setting's name or label in the Insteon device catalog, such as `rampRate`.
  public var name: String

  /// The value as given, such as `0.5 s`, `50%`, `on` or `0x1C`.
  public var value: String

  /// The button or group, for a setting that's per button, or `nil` for button 1.
  public var button: UInt8?

  /// Creates a request.
  ///
  /// - Parameters:
  ///   - name: The setting's name or label.
  ///   - value: The value as given.
  ///   - button: The button or group, or `nil` for button 1. Defaults to `nil`.
  public init(name: String, value: String, button: UInt8? = nil) {

    self.name = name
    self.value = value
    self.button = button

  }

}

/// How `insteon discover` looks for Hubs.
public struct DiscoverOptions: Hashable, Sendable {

  /// Whether to ask every address on the local private subnets.
  public var searchesLocalNetwork: Bool

  /// Whether to ask Insteon Connect, which sees the network's public IP address.
  public var asksInsteonConnect: Bool

  /// Whether the local search asks every address, rather than stopping at the first Hub.
  public var searchesAllAddresses: Bool

  /// Whether to ask Hubs found at a private address for Get IM Info, which sends the Hub's
  /// user name and password to each one asked.
  public var identifiesHubs: Bool

  /// The one Hub to ask for Get IM Info, from `--identify HOST[:PORT]`, or `nil` to ask about
  /// each Hub found.
  public var identifyTarget: HubAddress?

  /// Creates discovery options.
  ///
  /// - Parameters:
  ///   - searchesLocalNetwork: Whether to search the local network. Defaults to `true`.
  ///   - asksInsteonConnect: Whether to ask Insteon Connect. Defaults to `false`, so the
  ///     network's public IP address is shared only when asked.
  ///   - searchesAllAddresses: Whether the local search goes on after the first Hub.
  ///     Defaults to `false`.
  ///   - identifiesHubs: Whether to ask Hubs found for Get IM Info with the configured
  ///     credentials. Defaults to `false`, so the password is sent only when asked.
  ///   - identifyTarget: The one Hub to ask, or `nil` to ask about each Hub found. Defaults
  ///     to `nil`.
  public init(
    searchesLocalNetwork: Bool = true,
    asksInsteonConnect: Bool = false,
    searchesAllAddresses: Bool = false,
    identifiesHubs: Bool = false,
    identifyTarget: HubAddress? = nil
  ) {

    self.searchesLocalNetwork = searchesLocalNetwork
    self.asksInsteonConnect = asksInsteonConnect
    self.searchesAllAddresses = searchesAllAddresses
    self.identifiesHubs = identifiesHubs
    self.identifyTarget = identifyTarget

  }

}

/// A Hub named on the command line by its host and, optionally, its port.
public struct HubAddress: Hashable, Sendable {

  /// The Hub's host name or IP address.
  public var host: String

  /// The port of the Hub's HTTP interface, or `nil` for the Hub's default port.
  public var port: Int?

  /// Creates a Hub's address.
  ///
  /// - Parameters:
  ///   - host: The Hub's host name or IP address.
  ///   - port: The port of the Hub's HTTP interface, or `nil` for the Hub's default port.
  public init(host: String, port: Int? = nil) {

    self.host = host
    self.port = port

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

  /// The modem's ALL-Link group when none is given: group 0, as Insteon's Hub app and the
  /// catalog's From a Hub procedures link devices.
  public static let defaultGroup: AllLinkGroupNumber = 0

  /// The device's group sent with Enter Linking Mode, as its cmd2: group 1, a single-group
  /// device's only group and a multi-group device's first.
  public static let deviceGroup: AllLinkGroupNumber = 1

  /// The device to link by its address, without its SET button, or `nil` to wait for any
  /// device's SET button.
  public var device: InsteonAddress?

  /// The modem's ALL-Link group.
  public var group: AllLinkGroupNumber

  /// The modem's role in the link.
  public var role: LinkingRole

  /// Whether to link the device back after the modem links as its controller, so the modem
  /// becomes its responder and hears it, without a second SET button press:
  /// `TwoWayLinking.whenDeviceControls` by default, `TwoWayLinking.always` with `--two-way`,
  /// and `TwoWayLinking.never` with `--one-way`.
  public var twoWay: TwoWayLinking

  /// How many seconds to wait for the SET button, or `nil` for the library's default.
  public var timeoutSeconds: Int?

  /// Whether `--group` was given, even with the default group, so the device is linked in
  /// that group rather than by the Insteon device catalog's links to a Hub.
  public var isGroupGiven: Bool

  /// Whether the Insteon device catalog's links to a Hub may be made: the modem is the
  /// controller, not in either role, and no group was given. The library still checks the
  /// other options.
  public var followsCatalogLegs: Bool {

    role == .controller && !isGroupGiven

  }

  /// Creates linking options.
  ///
  /// - Parameters:
  ///   - device: The device to link by its address, or `nil` for any device's SET button.
  ///     Defaults to `nil`.
  ///   - group: The modem's ALL-Link group. Defaults to ``LinkOptions/defaultGroup``, group 0.
  ///   - role: The modem's role. Defaults to ``LinkingRole/controller``.
  ///   - twoWay: Whether to link the device back. Defaults to
  ///     `TwoWayLinking.whenDeviceControls`.
  ///   - timeoutSeconds: How many seconds to wait, or `nil` for the library's default.
  ///     Defaults to `nil`.
  ///   - isGroupGiven: Whether `--group` was given, or `nil` for whether `group` isn't the
  ///     default. Defaults to `nil`.
  public init(
    device: InsteonAddress? = nil,
    group: AllLinkGroupNumber = LinkOptions.defaultGroup,
    role: LinkingRole = .controller,
    twoWay: TwoWayLinking = .whenDeviceControls,
    timeoutSeconds: Int? = nil,
    isGroupGiven: Bool? = nil
  ) {

    self.device = device
    self.group = group
    self.role = role
    self.twoWay = twoWay
    self.timeoutSeconds = timeoutSeconds
    self.isGroupGiven = isGroupGiven ?? (group != LinkOptions.defaultGroup)

  }

}

/// How `insteon unlink` removes a link.
public struct UnlinkOptions: Hashable, Sendable {

  /// The device to unlink, or `nil` for whichever device's SET button is pressed. With a
  /// device, only its unlink is accepted, and its own steps are shown when they're known.
  public var device: InsteonAddress?

  /// The modem's ALL-Link group in the link, or `nil` when `--group` isn't given: then the
  /// group the modem's records for the device show, or group 0 without a device.
  public var group: AllLinkGroupNumber?

  /// The modem's role in the link: ``LinkingRole/controller`` or ``LinkingRole/responder``.
  public var role: LinkingRole

  /// How many seconds to wait for the SET button, or `nil` for the library's default.
  public var timeoutSeconds: Int?

  /// Whether to remove every link between the modem and ``UnlinkOptions/device``, in both
  /// directions, without its SET button, as `--all` asks.
  public var removesAllLinks: Bool

  /// Creates unlinking options.
  ///
  /// - Parameters:
  ///   - device: The device to unlink, or `nil` for any device. Defaults to `nil`.
  ///   - group: The modem's ALL-Link group, or `nil` for the group the modem's records for
  ///     the device show, or else ``LinkOptions/defaultGroup``, group 0. Defaults to `nil`.
  ///   - role: The modem's role. Defaults to ``LinkingRole/controller``.
  ///   - timeoutSeconds: How many seconds to wait, or `nil` for the library's default.
  ///     Defaults to `nil`.
  ///   - removesAllLinks: Whether to remove every link with the device without its SET
  ///     button. Defaults to `false`.
  public init(
    device: InsteonAddress? = nil,
    group: AllLinkGroupNumber? = nil,
    role: LinkingRole = .controller,
    timeoutSeconds: Int? = nil,
    removesAllLinks: Bool = false
  ) {

    self.device = device
    self.group = group
    self.role = role
    self.timeoutSeconds = timeoutSeconds
    self.removesAllLinks = removesAllLinks

  }

}

/// How `insteon remove` removes a device from the network.
public struct RemoveOptions: Hashable, Sendable {

  /// The device to remove.
  public var device: InsteonAddress

  /// Whether to read the ALL-Link databases of the other devices the identity cache knows,
  /// and list the records that still name the device, as `--scan` asks.
  public var scansOtherDevices: Bool

  /// Whether to delete the modem's records for the device directly when its links can't be
  /// removed through it, because it's gone, as `--force-modem-side` asks.
  public var forcesModemSide: Bool

  /// Whether to remove the device without asking first, as `--yes` asks.
  public var assumesYes: Bool

  /// How many seconds to wait for each link to be removed, or `nil` for the library's
  /// default.
  public var timeoutSeconds: Int?

  /// Creates removal options.
  ///
  /// - Parameters:
  ///   - device: The device to remove.
  ///   - scansOtherDevices: Whether to look for records that name the device in other
  ///     devices' ALL-Link databases. Defaults to `false`.
  ///   - forcesModemSide: Whether to delete the modem's records for a device that's gone.
  ///     Defaults to `false`.
  ///   - assumesYes: Whether to remove the device without asking. Defaults to `false`.
  ///   - timeoutSeconds: How many seconds to wait for each link, or `nil` for the library's
  ///     default. Defaults to `nil`.
  public init(
    device: InsteonAddress,
    scansOtherDevices: Bool = false,
    forcesModemSide: Bool = false,
    assumesYes: Bool = false,
    timeoutSeconds: Int? = nil
  ) {

    self.device = device
    self.scansOtherDevices = scansOtherDevices
    self.forcesModemSide = forcesModemSide
    self.assumesYes = assumesYes
    self.timeoutSeconds = timeoutSeconds

  }

  /// Whether the command asks the person before it removes the device: unless `--yes` is
  /// given, it asks at a terminal, and refuses to go on without one.
  ///
  /// - Parameter readsFromTerminal: Whether standard input is a terminal.
  /// - Returns: `true` to ask first, or `false` to remove the device without asking.
  /// - Throws: ``ArgumentError/confirmationNeeded(subcommand:)`` when standard input isn't a
  ///   terminal and `--yes` isn't given.
  public func asksForConfirmation(readsFromTerminal: Bool) throws(ArgumentError) -> Bool {

    if assumesYes {

      return false

    }

    guard readsFromTerminal else {

      throw ArgumentError.confirmationNeeded(subcommand: "remove")

    }

    return true

  }

}

/// How `insteon links` lists the modem's ALL-Link database.
public struct LinksOptions: Hashable, Sendable {

  /// Whether to ask each linked device for its identity with ID Request, one request per
  /// device, rather than naming only devices whose identity was learned before.
  public var identifiesDevices: Bool

  /// Creates options for listing links.
  ///
  /// - Parameter identifiesDevices: Whether to send each device ID Request. Defaults to
  ///   `false`.
  public init(identifiesDevices: Bool = false) {

    self.identifiesDevices = identifiesDevices

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

  /// Turns the device on with Light On Fast, ignoring its ramp rate, at a level from 0 to 100
  /// percent, or fully on when `nil`.
  case onFast(levelPercent: Int?)

  /// Turns the device off with Light Off.
  case off

  /// Turns the device off with Light Off Fast, ignoring its ramp rate.
  case offFast

  /// Changes the device to a level from 0 to 100 percent at once, with Light Instant Change.
  case instant(levelPercent: Int)

  /// Makes the device beep with Beep.
  case beep

  /// Reads the device's settings the Insteon device catalog describes; advanced ones only when
  /// `showsAdvanced`.
  case settings(showsAdvanced: Bool)

  /// Changes one of the device's settings.
  case set(SettingRequest)

  /// Sends the device a message as given, for exploring.
  case send(DirectMessageRequest)

  /// Asks for the device's level with Light Status Request.
  case status

  /// Reads the device's ALL-Link database.
  case links

}

/// How `insteon watch` prints what the modem hears.
public struct WatchOptions: Hashable, Sendable {

  /// Whether to print each message's bytes, as the modem sent them, and the kind of every
  /// other reply, as well as the events read from them.
  public var printsRawReplies: Bool

  /// Creates watch options.
  ///
  /// - Parameter printsRawReplies: Whether to print each message's bytes. Defaults to `false`.
  public init(printsRawReplies: Bool = false) {

    self.printsRawReplies = printsRawReplies

  }

}
