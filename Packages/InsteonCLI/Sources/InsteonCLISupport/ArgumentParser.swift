import InsteonCore

extension Invocation {

  /// The subcommands, in the order the help lists them.
  public static let subcommandNames = ["discover", "info", "links", "link", "unlink", "remove", "device", "scene", "beep", "modem", "watch", "catalog"]

  /// Other names for subcommands: `group` for `scene`.
  public static let subcommandAliases = ["group": "scene"]

  /// Reads a command line, without the program's name.
  ///
  /// The command's own options, `--hub`, `--serial`, `--env-file`, `--json` and `--help`, can
  /// come before or after the subcommand. An option's value can follow it as the next argument or after
  /// `=`, as in `--hub=192.168.1.20`. With no arguments, or with `--help`, the invocation
  /// prints help.
  ///
  /// The command takes no credentials: the Hub's user name and password come only from the
  /// environment or the ``EnvironmentFile``, so they stay out of shell history and process
  /// lists. A `--hub` with `@` in it, as in a URL with a user name and password, is refused
  /// without repeating it.
  ///
  /// - Parameter arguments: The arguments, such as `CommandLine.arguments.dropFirst()`.
  /// - Returns: The invocation.
  /// - Throws: ``ArgumentError`` if the command line isn't one the command can run.
  public static func parse(_ arguments: [String]) throws(ArgumentError) -> Invocation {

    var hub: String?
    var serialPath: String?
    var envFilePath: String?
    var printsJSON = false
    var asksForHelp = false
    var rest: [String] = []
    var index = 0

    while index < arguments.count {

      let argument = arguments[index]
      let (name, inlineValue) = split(argument)
      index += 1

      switch name {
      case "--hub":
        let text = try value(of: name, inline: inlineValue, in: arguments, at: &index)

        guard !text.contains("@") else {

          throw ArgumentError.credentialsInHub

        }

        hub = text
      case "--serial":
        serialPath = try value(of: name, inline: inlineValue, in: arguments, at: &index)
      case "--env-file":
        envFilePath = try value(of: name, inline: inlineValue, in: arguments, at: &index)
      case "--json":
        try expectNoValue(name, inlineValue)
        printsJSON = true
      case "-h", "--help":
        try expectNoValue(name, inlineValue)
        asksForHelp = true
      case "--":
        rest.append(contentsOf: arguments[index...])
        index = arguments.count
      default:
        rest.append(argument)
      }

    }

    let subcommand = try parseSubcommand(rest, asksForHelp: asksForHelp)

    return Invocation(hub: hub, serialPath: serialPath, envFilePath: envFilePath, printsJSON: printsJSON, subcommand: subcommand)

  }

  // MARK: - Subcommands

  private static func parseSubcommand(_ arguments: [String], asksForHelp: Bool) throws(ArgumentError) -> Subcommand {

    guard arguments.first != nil else {

      return .help(topic: nil)

    }

    let rest = Array(arguments.dropFirst())

    if arguments[0] == "help" {

      guard let topic = rest.first else {

        return .help(topic: nil)

      }

      // An option's value isn't repeated, in case it's something private.
      if topic.hasPrefix("-") {

        throw ArgumentError.unknownOption(split(topic).name, subcommand: nil)

      }

      let resolvedTopic: String = subcommandAliases[topic] ?? topic

      guard subcommandNames.contains(resolvedTopic) else {

        throw ArgumentError.unknownHelpTopic(topic)

      }

      if rest.count > 1 {

        throw unexpected(rest[1], subcommand: "help")

      }

      return .help(topic: resolvedTopic)

    }

    if arguments.first?.hasPrefix("-") == true {

      throw ArgumentError.unknownOption(split(arguments[0]).name, subcommand: nil)

    }

    let name: String = subcommandAliases[arguments[0]] ?? arguments[0]

    guard subcommandNames.contains(name) else {

      throw ArgumentError.unknownCommand(arguments[0])

    }

    if asksForHelp {

      return .help(topic: name)

    }

    switch name {
    case "discover":
      return try .discover(parseDiscover(rest))
    case "info":
      try expectNoArguments(rest, subcommand: name)
      return .info
    case "links":
      return try .links(parseLinks(rest))
    case "link":
      return try parseLink(rest)
    case "unlink":
      return try .unlink(parseUnlink(rest))
    case "remove":
      return try .remove(parseRemove(rest))
    case "device":
      return try parseDevice(rest)
    case "scene":
      return try parseScene(rest)
    case "beep":
      return try parseBeep(rest)
    case "modem":
      return try parseModem(rest)
    case "catalog":
      return try parseCatalog(rest)
    default:
      return try .watch(parseWatch(rest))
    }

  }

  private static func parseDiscover(_ arguments: [String]) throws(ArgumentError) -> DiscoverOptions {

    var searchesLocalNetwork = false
    var asksInsteonConnect = false
    var searchesAllAddresses = false
    var identifiesHubs = false
    var identifyTarget: HubAddress?
    var index = 0

    while index < arguments.count {

      let argument = arguments[index]
      let (name, inlineValue) = split(argument)
      index += 1

      switch name {
      case "--local":
        try expectNoValue(name, inlineValue)
        searchesLocalNetwork = true
      case "--insteon-connect":
        try expectNoValue(name, inlineValue)
        asksInsteonConnect = true
      case "--all":
        try expectNoValue(name, inlineValue)
        searchesAllAddresses = true
      case "--identify":
        identifiesHubs = true

        // The Hub to identify is optional: after `=`, or as the next argument when it isn't
        // an option.
        let hasNextValue = index < arguments.count && !arguments[index].hasPrefix("-")

        guard inlineValue != nil || hasNextValue else {

          continue

        }

        let text = try value(of: name, inline: inlineValue, in: arguments, at: &index)

        identifyTarget = try hubAddress(text, option: name)
      default:
        throw unexpected(argument, subcommand: "discover")
      }

    }

    // Without --insteon-connect, only the local network is searched, so Insteon Connect is
    // asked only when someone asks for it.
    return DiscoverOptions(
      searchesLocalNetwork: searchesLocalNetwork || !asksInsteonConnect,
      asksInsteonConnect: asksInsteonConnect,
      searchesAllAddresses: searchesAllAddresses,
      identifiesHubs: identifiesHubs,
      identifyTarget: identifyTarget
    )

  }

  private static func parseLinks(_ arguments: [String]) throws(ArgumentError) -> LinksOptions {

    var options = LinksOptions()

    for argument in arguments {

      let (name, inlineValue) = split(argument)

      guard name == "--identify" else {

        throw unexpected(argument, subcommand: "links")

      }

      try expectNoValue(name, inlineValue)
      options.identifiesDevices = true

    }

    return options

  }

  private static func parseLink(_ arguments: [String]) throws(ArgumentError) -> Subcommand {

    var options = LinkOptions()
    var roleOption: String?
    var twoWayOption: String?
    var otherOption: String?
    var deviceArgument: String?
    var cancels = false
    var usesDatabase = false
    var database = DatabaseWriteOptions()
    var databaseOnlyOption: String?
    var index = 0

    while index < arguments.count {

      let argument = arguments[index]
      let (name, inlineValue) = split(argument)
      index += 1

      if !argument.hasPrefix("-") {

        options.device = try address(argument, after: deviceArgument, subcommand: "link")
        deviceArgument = argument
        continue

      }

      switch name {
      case "--group":
        options.group = try group(value(of: name, inline: inlineValue, in: arguments, at: &index), option: name)
        options.isGroupGiven = true
        otherOption = name
      case "--timeout":
        options.timeoutSeconds = try seconds(value(of: name, inline: inlineValue, in: arguments, at: &index), option: name)
        otherOption = name
      case "--controller", "--responder", "--either":
        try expectNoValue(name, inlineValue)

        if let roleOption, roleOption != name {

          throw ArgumentError.conflictingOptions(roleOption, name)

        }

        roleOption = name
        options.role = LinkingRole(rawValue: String(name.dropFirst(2))) ?? .controller
      case "--two-way", "--one-way":
        try expectNoValue(name, inlineValue)

        if let twoWayOption, twoWayOption != name {

          throw ArgumentError.conflictingOptions(twoWayOption, name)

        }

        twoWayOption = name
        options.twoWay = name == "--two-way" ? .always : .never
        otherOption = name
      case "--cancel":
        try expectNoValue(name, inlineValue)
        cancels = true
      case "--database":
        try expectNoValue(name, inlineValue)
        usesDatabase = true
      case "--dry-run":
        try expectNoValue(name, inlineValue)
        database.isDryRun = true
        databaseOnlyOption = databaseOnlyOption ?? name
      case "-y", "--yes":
        try expectNoValue(name, inlineValue)
        database.assumesYes = true
        databaseOnlyOption = databaseOnlyOption ?? name
      default:
        throw unexpected(argument, subcommand: "link")
      }

    }

    // --database writes the links the Insteon device catalog gives one device, so it takes no
    // role, group, timeout or way of linking back.
    if usesDatabase {

      if let other = roleOption ?? otherOption ?? (cancels ? "--cancel" : nil) {

        throw ArgumentError.conflictingOptions("--database", other)

      }

      if deviceArgument == nil {

        throw ArgumentError.missingArgument("ADDRESS with --database", subcommand: "link")

      }

      options.database = database

      return .link(options)

    }

    if let databaseOnlyOption {

      throw ArgumentError.missingArgument("--database with \(databaseOnlyOption)", subcommand: "link")

    }

    guard cancels else {

      // Two-way linking starts with the modem as the controller.
      if options.twoWay == .always, let roleOption, roleOption != "--controller" {

        throw ArgumentError.conflictingOptions("--two-way", roleOption)

      }

      // A device linked by its address is told which role to take, so it can't choose.
      if let deviceArgument, options.role == .either {

        throw ArgumentError.conflictingOptions("--either", deviceArgument)

      }

      return .link(options)

    }

    if let other = roleOption ?? otherOption ?? deviceArgument {

      throw ArgumentError.conflictingOptions("--cancel", other)

    }

    return .cancelLinking

  }

  private static func parseUnlink(_ arguments: [String]) throws(ArgumentError) -> UnlinkOptions {

    var options = UnlinkOptions()
    var roleOption: String?
    var groupOption: String?
    var timeoutOption: String?
    var deviceArgument: String?
    var usesDatabase = false
    var database = DatabaseWriteOptions()
    var databaseOnlyOption: String?
    var index = 0

    while index < arguments.count {

      let argument = arguments[index]
      let (name, inlineValue) = split(argument)
      index += 1

      if !argument.hasPrefix("-") {

        options.device = try address(argument, after: deviceArgument, subcommand: "unlink")
        deviceArgument = argument
        continue

      }

      switch name {
      case "--group":
        options.group = try group(value(of: name, inline: inlineValue, in: arguments, at: &index), option: name)
        groupOption = name
      case "--timeout":
        options.timeoutSeconds = try seconds(value(of: name, inline: inlineValue, in: arguments, at: &index), option: name)
        timeoutOption = name
      case "--all":
        try expectNoValue(name, inlineValue)
        options.removesAllLinks = true
      case "--controller", "--responder":
        try expectNoValue(name, inlineValue)

        if let roleOption, roleOption != name {

          throw ArgumentError.conflictingOptions(roleOption, name)

        }

        roleOption = name
        options.role = name == "--responder" ? .responder : .controller
      case "--database":
        try expectNoValue(name, inlineValue)
        usesDatabase = true
      case "--orphans":
        try expectNoValue(name, inlineValue)
        database.removesOrphans = true
        databaseOnlyOption = databaseOnlyOption ?? name
      case "--dry-run":
        try expectNoValue(name, inlineValue)
        database.isDryRun = true
        databaseOnlyOption = databaseOnlyOption ?? name
      case "-y", "--yes":
        try expectNoValue(name, inlineValue)
        database.assumesYes = true
        databaseOnlyOption = databaseOnlyOption ?? name
      default:
        throw unexpected(argument, subcommand: "unlink")
      }

    }

    // --database removes every link between the modem and one device, so it takes no role,
    // group or timeout.
    if usesDatabase {

      if let other = groupOption ?? roleOption ?? timeoutOption {

        throw ArgumentError.conflictingOptions("--database", other)

      }

      if deviceArgument == nil {

        throw ArgumentError.missingArgument("ADDRESS with --database", subcommand: "unlink")

      }

      options.database = database

      return options

    }

    if let databaseOnlyOption {

      throw ArgumentError.missingArgument("--database with \(databaseOnlyOption)", subcommand: "unlink")

    }

    // --all removes every link with one device, in each of its groups and in both roles.
    if options.removesAllLinks {

      if let other = groupOption ?? roleOption {

        throw ArgumentError.conflictingOptions("--all", other)

      }

      if deviceArgument == nil {

        throw ArgumentError.missingArgument("ADDRESS with --all", subcommand: "unlink")

      }

    }

    return options

  }

  private static func parseRemove(_ arguments: [String]) throws(ArgumentError) -> RemoveOptions {

    var device: InsteonAddress?
    var deviceArgument: String?
    var scansOtherDevices = false
    var forcesModemSide = false
    var assumesYes = false
    var timeoutSeconds: Int?
    var index = 0

    while index < arguments.count {

      let argument = arguments[index]
      let (name, inlineValue) = split(argument)
      index += 1

      if !argument.hasPrefix("-") {

        device = try address(argument, after: deviceArgument, subcommand: "remove")
        deviceArgument = argument
        continue

      }

      switch name {
      case "--scan":
        try expectNoValue(name, inlineValue)
        scansOtherDevices = true
      case "--force-modem-side":
        try expectNoValue(name, inlineValue)
        forcesModemSide = true
      case "-y", "--yes":
        try expectNoValue(name, inlineValue)
        assumesYes = true
      case "--timeout":
        timeoutSeconds = try seconds(value(of: name, inline: inlineValue, in: arguments, at: &index), option: name)
      default:
        throw unexpected(argument, subcommand: "remove")
      }

    }

    guard let device else {

      throw ArgumentError.missingArgument("a device's ADDRESS, such as 1A.2B.3C", subcommand: "remove")

    }

    return RemoveOptions(
      device: device,
      scansOtherDevices: scansOtherDevices,
      forcesModemSide: forcesModemSide,
      assumesYes: assumesYes,
      timeoutSeconds: timeoutSeconds
    )

  }

  private static func parseDevice(_ arguments: [String]) throws(ArgumentError) -> Subcommand {

    guard let text = arguments.first else {

      throw ArgumentError.missingAddress

    }

    if text.hasPrefix("-") {

      throw ArgumentError.unknownOption(split(text).name, subcommand: "device")

    }

    guard let address = InsteonAddress(text) else {

      throw ArgumentError.invalidAddress(text)

    }

    guard arguments.count > 1 else {

      throw ArgumentError.missingDeviceAction

    }

    let action = arguments[1]
    let rest = Array(arguments.dropFirst(2))

    switch action {
    case "id":
      try expectNoArguments(rest, subcommand: "device")
      return .device(address, .id)
    case "ping":
      try expectNoArguments(rest, subcommand: "device")
      return .device(address, .ping)
    case "on":
      let isFast: Bool = rest.contains("--fast")
      let others: [String] = rest.filter { $0 != "--fast" }

      guard let level = others.first else {

        return .device(address, isFast ? .onFast(levelPercent: nil) : .on(levelPercent: nil))

      }

      try expectNoArguments(Array(others.dropFirst()), subcommand: "device")

      // An option's value isn't repeated, in case it's something private.
      if level.hasPrefix("-") {

        throw unexpected(level, subcommand: "device")

      }

      let levelPercent: Int = try percent(level, action: "on")

      return .device(address, isFast ? .onFast(levelPercent: levelPercent) : .on(levelPercent: levelPercent))
    case "off":
      let isFast: Bool = rest.contains("--fast")

      try expectNoArguments(rest.filter { $0 != "--fast" }, subcommand: "device")
      return .device(address, isFast ? .offFast : .off)
    case "instant":
      guard let level = rest.first, !level.hasPrefix("-") else {

        if let option = rest.first {

          throw unexpected(option, subcommand: "device")

        }

        throw ArgumentError.missingArgument("a level, such as 50%", subcommand: "device ADDRESS instant")

      }

      try expectNoArguments(Array(rest.dropFirst()), subcommand: "device")
      return try .device(address, .instant(levelPercent: percent(level, action: "instant")))
    case "beep":
      try expectNoArguments(rest, subcommand: "device")
      return .device(address, .beep)
    case "settings":
      return try .device(address, .settings(showsAdvanced: parseSettings(rest)))
    case "set":
      return try .device(address, .set(parseSet(rest)))
    case "send":
      return try .device(address, .send(parseSend(rest)))
    case "status":
      try expectNoArguments(rest, subcommand: "device")
      return .device(address, .status)
    case "links":
      try expectNoArguments(rest, subcommand: "device")
      return .device(address, .links)
    case "selftest":
      return try .device(address, parseSelfTest(rest))
    default:
      if action.hasPrefix("-") {

        throw ArgumentError.unknownOption(split(action).name, subcommand: "device")

      }

      throw ArgumentError.unknownDeviceAction(action)
    }

  }

  private static func parseSelfTest(_ arguments: [String]) throws(ArgumentError) -> DeviceAction {

    var actuates = false
    var showsChecklist = false

    for argument in arguments {

      let (name, inlineValue) = split(argument)

      switch name {
      case "--actuate":
        try expectNoValue(name, inlineValue)
        actuates = true
      case "--checklist":
        try expectNoValue(name, inlineValue)
        showsChecklist = true
      default:
        throw unexpected(argument, subcommand: "device")
      }

    }

    return .selfTest(actuates: actuates, showsChecklist: showsChecklist)

  }

  private static func parseSettings(_ arguments: [String]) throws(ArgumentError) -> Bool {

    var showsAdvanced = false

    for argument in arguments {

      let (name, inlineValue) = split(argument)

      guard name == "--advanced" else {

        throw unexpected(argument, subcommand: "device")

      }

      try expectNoValue(name, inlineValue)
      showsAdvanced = true

    }

    return showsAdvanced

  }

  private static func parseSet(_ arguments: [String]) throws(ArgumentError) -> SettingRequest {

    var positional: [String] = []
    var button: UInt8?
    var index = 0

    while index < arguments.count {

      let argument = arguments[index]
      let (name, inlineValue) = split(argument)
      index += 1

      // A negative number isn't an option.
      if !argument.hasPrefix("--") {

        positional.append(argument)
        continue

      }

      guard name == "--button" else {

        throw unexpected(argument, subcommand: "device")

      }

      let text = try value(of: name, inline: inlineValue, in: arguments, at: &index)

      guard let number = UInt8(text), (1...254).contains(number) else {

        throw ArgumentError.invalidValue(option: name, value: text, expected: "a button or group from 1 to 254")

      }

      button = number

    }

    guard positional.count >= 1 else {

      throw ArgumentError.missingArgument("a setting's NAME and VALUE, such as rampRate 0.5s", subcommand: "device ADDRESS set")

    }

    guard positional.count >= 2 else {

      throw ArgumentError.missingArgument("a VALUE for \(positional[0])", subcommand: "device ADDRESS set")

    }

    // A value with spaces, such as 0.5 s, can be given as two arguments.
    let value: String = positional.dropFirst().joined(separator: " ")

    return SettingRequest(name: positional[0], value: value, button: button)

  }

  private static func parseSend(_ arguments: [String]) throws(ArgumentError) -> DirectMessageRequest {

    var bytes: [UInt8] = []
    var userData: [UInt8]?
    var hasChecksum = true
    var waitSeconds = 3
    var index = 0

    while index < arguments.count {

      let argument = arguments[index]
      let (name, inlineValue) = split(argument)
      index += 1

      if !argument.hasPrefix("-") {

        guard bytes.count < 2 else {

          throw unexpected(argument, subcommand: "device")

        }

        guard let byte = HexInput.byte(argument) else {

          throw ArgumentError.invalidValue(option: bytes.isEmpty ? "CMD1" : "CMD2", value: argument, expected: "a byte in hexadecimal, such as 0x2E")

        }

        bytes.append(byte)
        continue

      }

      switch name {
      case "--extended":
        try expectNoValue(name, inlineValue)

        var data: [UInt8] = []

        // The data bytes follow, up to the next option.
        while index < arguments.count, !arguments[index].hasPrefix("-") {

          guard let byte = HexInput.byte(arguments[index]), data.count < 14 else {

            throw ArgumentError.invalidValue(option: name, value: arguments[index], expected: "up to 14 bytes in hexadecimal, D1 through D14")

          }

          data.append(byte)
          index += 1

        }

        userData = data
      case "--no-checksum":
        try expectNoValue(name, inlineValue)
        hasChecksum = false
      case "--wait":
        waitSeconds = try seconds(value(of: name, inline: inlineValue, in: arguments, at: &index), option: name)
      default:
        throw unexpected(argument, subcommand: "device")
      }

    }

    guard bytes.count == 2 else {

      throw ArgumentError.missingArgument("CMD1 and CMD2, such as 0x19 0x00", subcommand: "device ADDRESS send")

    }

    // Poke is refused before the modem is opened. Whether a protected Set Operating Flags is
    // sent depends on the device's command set, so the network decides that.
    if ProtectedCommand(command1: bytes[0], command2: bytes[1]) == .poke {

      throw ArgumentError.neverSent(.protected(.poke), by: .deviceSend)

    }

    // All 14 bytes given are sent as they are.
    let checksums: Bool = hasChecksum && (userData?.count ?? 0) < 14

    return DirectMessageRequest(command1: bytes[0], command2: bytes[1], userData: userData, hasChecksum: checksums, waitSeconds: waitSeconds)

  }

  private static func parseScene(_ arguments: [String]) throws(ArgumentError) -> Subcommand {

    if let option = arguments.first(where: { $0.hasPrefix("-") }) {

      throw unexpected(option, subcommand: "scene")

    }

    guard arguments.count == 2 else {

      if arguments.count > 2 {

        throw unexpected(arguments[2], subcommand: "scene")

      }

      throw ArgumentError.missingArgument("a GROUP and on or off, such as 3 on", subcommand: "scene")

    }

    let group: AllLinkGroupNumber = try Self.group(arguments[0], option: "GROUP")

    switch arguments[1] {
    case "on":
      return .scene(group: group, isOn: true)
    case "off":
      return .scene(group: group, isOn: false)
    default:
      throw ArgumentError.invalidValue(option: "scene", value: arguments[1], expected: "on or off")
    }

  }

  private static func parseBeep(_ arguments: [String]) throws(ArgumentError) -> Subcommand {

    var isDouble = false

    for argument in arguments {

      let (name, inlineValue) = split(argument)

      guard name == "--double" else {

        throw unexpected(argument, subcommand: "beep")

      }

      try expectNoValue(name, inlineValue)
      isDouble = true

    }

    return .beep(isDouble: isDouble)

  }

  private static func parseModem(_ arguments: [String]) throws(ArgumentError) -> Subcommand {

    guard let action = arguments.first else {

      throw ArgumentError.missingArgument("an action: send", subcommand: "modem")

    }

    guard action == "send" else {

      throw unexpected(action, subcommand: "modem")

    }

    var text: [String] = []
    var forces = false
    var waitSeconds = 3
    var index = 1

    while index < arguments.count {

      let argument = arguments[index]
      let (name, inlineValue) = split(argument)
      index += 1

      if !argument.hasPrefix("-") {

        text.append(argument)
        continue

      }

      switch name {
      case "--force":
        try expectNoValue(name, inlineValue)
        forces = true
      case "--wait":
        waitSeconds = try seconds(value(of: name, inline: inlineValue, in: arguments, at: &index), option: name)
      default:
        throw unexpected(argument, subcommand: "modem")
      }

    }

    guard !text.isEmpty else {

      throw ArgumentError.missingArgument("the command's bytes in hexadecimal, such as 0277", subcommand: "modem send")

    }

    let joined: String = text.joined(separator: " ")

    guard let bytes = HexInput.bytes(joined), bytes.count <= 32 else {

      throw ArgumentError.invalidValue(option: "send", value: joined, expected: "up to 32 bytes in hexadecimal, such as 0277 or 02 77 01")

    }

    guard SerialCommandPolicy.isSerialCommand(bytes) else {

      throw ArgumentError.invalidValue(option: "send", value: joined, expected: "a serial command, which starts with 02")

    }

    // Refused before the modem is opened; ModemSession checks the bytes again.
    switch SerialCommandPolicy.refusal(of: bytes, forcing: forces) {
    case nil:
      break
    case let .serialCommand(reason)?:
      throw ArgumentError.refusedSerialCommand(reason)
    case let refusal?:
      throw ArgumentError.neverSent(refusal, by: .modemSend)
    }

    return .modemSend(RawSerialRequest(bytes: bytes, waitSeconds: waitSeconds, isForced: forces))

  }

  private static func parseCatalog(_ arguments: [String]) throws(ArgumentError) -> Subcommand {

    guard let action = arguments.first else {

      return .catalog

    }

    guard action == "update" else {

      throw unexpected(action, subcommand: "catalog")

    }

    try expectNoArguments(Array(arguments.dropFirst()), subcommand: "catalog")

    return .catalogUpdate

  }

  private static func parseWatch(_ arguments: [String]) throws(ArgumentError) -> WatchOptions {

    var options = WatchOptions()

    for argument in arguments {

      let (name, inlineValue) = split(argument)

      guard name == "--raw" else {

        throw unexpected(argument, subcommand: "watch")

      }

      try expectNoValue(name, inlineValue)
      options.printsRawReplies = true

    }

    return options

  }

  // MARK: - Values

  /// A device's address given as an argument, where only one can be given.
  ///
  /// - Parameters:
  ///   - text: The argument.
  ///   - earlier: The address argument given before, if any.
  ///   - subcommand: The subcommand, for the error.
  private static func address(_ text: String, after earlier: String?, subcommand: String) throws(ArgumentError) -> InsteonAddress {

    if earlier != nil {

      throw ArgumentError.unexpectedArgument(text, subcommand: subcommand)

    }

    guard let address = InsteonAddress(text) else {

      throw ArgumentError.invalidAddress(text)

    }

    return address

  }

  /// Splits `--name=value` into its name and value. Anything else is a name without a value.
  private static func split(_ argument: String) -> (name: String, value: String?) {

    guard argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") else {

      return (argument, nil)

    }

    return (String(argument[..<equals]), String(argument[argument.index(after: equals)...]))

  }

  /// An option's value: the one after `=`, or else the next argument, which `index` then moves
  /// past.
  private static func value(of option: String, inline: String?, in arguments: [String], at index: inout Int) throws(ArgumentError) -> String {

    if let inline {

      guard !inline.isEmpty else {

        throw ArgumentError.missingValue(option: option)

      }

      return inline

    }

    guard index < arguments.count, !arguments[index].hasPrefix("--") else {

      throw ArgumentError.missingValue(option: option)

    }

    index += 1

    return arguments[index - 1]

  }

  private static func expectNoValue(_ option: String, _ value: String?) throws(ArgumentError) {

    if value != nil {

      throw ArgumentError.unexpectedValue(option: option)

    }

  }

  private static func expectNoArguments(_ arguments: [String], subcommand: String) throws(ArgumentError) {

    if let first = arguments.first {

      throw unexpected(first, subcommand: subcommand)

    }

  }

  /// The error for an argument a subcommand doesn't take: an unknown option, or an unexpected
  /// argument. An option's value isn't repeated, in case it's something private.
  private static func unexpected(_ argument: String, subcommand: String) -> ArgumentError {

    argument.hasPrefix("-")
      ? .unknownOption(split(argument).name, subcommand: subcommand)
      : .unexpectedArgument(argument, subcommand: subcommand)

  }

  /// A group number in decimal, from 0 to 254. Group 255 means every group, so a link can't be
  /// made in it.
  private static func group(_ text: String, option: String) throws(ArgumentError) -> AllLinkGroupNumber {

    guard let number = UInt8(text), number != 255 else {

      throw ArgumentError.invalidValue(option: option, value: text, expected: "a group number from 0 to 254")

    }

    return AllLinkGroupNumber(rawValue: number)

  }

  /// A Hub's `HOST` or `HOST:PORT`. A value with `@` in it, as in a URL with a user name and
  /// password, is refused without repeating it.
  private static func hubAddress(_ text: String, option: String) throws(ArgumentError) -> HubAddress {

    guard !text.contains("@") else {

      throw ArgumentError.credentialsInOption(option)

    }

    do {

      let parts = try ModemTarget.hostAndPort(text)

      return HubAddress(host: parts.host, port: parts.port)

    } catch {

      throw ArgumentError.invalidValue(option: option, value: text, expected: "HOST or HOST:PORT, such as 192.168.1.20")

    }

  }

  /// A whole number of seconds, from 1 to 3,600.
  private static func seconds(_ text: String, option: String) throws(ArgumentError) -> Int {

    guard let seconds = Int(text), (1...3_600).contains(seconds) else {

      throw ArgumentError.invalidValue(option: option, value: text, expected: "a number of seconds from 1 to 3600")

    }

    return seconds

  }

  /// A level from 0 to 100 percent, with or without a percent sign.
  private static func percent(_ text: String, action: String) throws(ArgumentError) -> Int {

    let digits = text.hasSuffix("%") ? String(text.dropLast()) : text

    guard let percent = Int(digits), (0...100).contains(percent) else {

      throw ArgumentError.invalidValue(option: action, value: text, expected: "a level from 0 to 100, such as 50%")

    }

    return percent

  }

}
