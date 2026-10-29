import InsteonProtocol

extension Invocation {

  /// The subcommands, in the order the help lists them.
  public static let subcommandNames = ["discover", "info", "links", "link", "unlink", "device", "watch"]

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

    guard let name = arguments.first else {

      return .help(topic: nil)

    }

    let rest = Array(arguments.dropFirst())

    if name == "help" {

      guard let topic = rest.first else {

        return .help(topic: nil)

      }

      // An option's value isn't repeated, in case it's something private.
      if topic.hasPrefix("-") {

        throw ArgumentError.unknownOption(split(topic).name, subcommand: nil)

      }

      guard subcommandNames.contains(topic) else {

        throw ArgumentError.unknownHelpTopic(topic)

      }

      if rest.count > 1 {

        throw unexpected(rest[1], subcommand: "help")

      }

      return .help(topic: topic)

    }

    if name.hasPrefix("-") {

      throw ArgumentError.unknownOption(split(name).name, subcommand: nil)

    }

    guard subcommandNames.contains(name) else {

      throw ArgumentError.unknownCommand(name)

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
      try expectNoArguments(rest, subcommand: name)
      return .links
    case "link":
      return try parseLink(rest)
    case "unlink":
      return try .unlink(parseUnlink(rest))
    case "device":
      return try parseDevice(rest)
    default:
      return try .watch(parseWatch(rest))
    }

  }

  private static func parseDiscover(_ arguments: [String]) throws(ArgumentError) -> DiscoverOptions {

    var searchesLocalNetwork = false
    var asksInsteonConnect = false

    for argument in arguments {

      let (name, inlineValue) = split(argument)

      switch name {
      case "--local":
        try expectNoValue(name, inlineValue)
        searchesLocalNetwork = true
      case "--insteon-connect":
        try expectNoValue(name, inlineValue)
        asksInsteonConnect = true
      default:
        throw unexpected(argument, subcommand: "discover")
      }

    }

    // Neither option searches only the local network, so Insteon Connect is asked only when
    // someone asks for it.
    guard searchesLocalNetwork || asksInsteonConnect else {

      return DiscoverOptions()

    }

    return DiscoverOptions(searchesLocalNetwork: searchesLocalNetwork, asksInsteonConnect: asksInsteonConnect)

  }

  private static func parseLink(_ arguments: [String]) throws(ArgumentError) -> Subcommand {

    var options = LinkOptions()
    var roleOption: String?
    var otherOption: String?
    var cancels = false
    var index = 0

    while index < arguments.count {

      let argument = arguments[index]
      let (name, inlineValue) = split(argument)
      index += 1

      switch name {
      case "--group":
        options.group = try group(value(of: name, inline: inlineValue, in: arguments, at: &index), option: name)
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
      case "--cancel":
        try expectNoValue(name, inlineValue)
        cancels = true
      default:
        throw unexpected(argument, subcommand: "link")
      }

    }

    guard cancels else {

      return .link(options)

    }

    if let other = roleOption ?? otherOption {

      throw ArgumentError.conflictingOptions("--cancel", other)

    }

    return .cancelLinking

  }

  private static func parseUnlink(_ arguments: [String]) throws(ArgumentError) -> UnlinkOptions {

    var options = UnlinkOptions()
    var roleOption: String?
    var index = 0

    while index < arguments.count {

      let argument = arguments[index]
      let (name, inlineValue) = split(argument)
      index += 1

      switch name {
      case "--group":
        options.group = try group(value(of: name, inline: inlineValue, in: arguments, at: &index), option: name)
      case "--timeout":
        options.timeoutSeconds = try seconds(value(of: name, inline: inlineValue, in: arguments, at: &index), option: name)
      case "--controller", "--responder":
        try expectNoValue(name, inlineValue)

        if let roleOption, roleOption != name {

          throw ArgumentError.conflictingOptions(roleOption, name)

        }

        roleOption = name
        options.role = name == "--responder" ? .responder : .controller
      default:
        throw unexpected(argument, subcommand: "unlink")
      }

    }

    return options

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
      guard let level = rest.first else {

        return .device(address, .on(levelPercent: nil))

      }

      try expectNoArguments(Array(rest.dropFirst()), subcommand: "device")

      // An option's value isn't repeated, in case it's something private.
      if level.hasPrefix("-") {

        throw unexpected(level, subcommand: "device")

      }

      return try .device(address, .on(levelPercent: percent(level)))
    case "off":
      try expectNoArguments(rest, subcommand: "device")
      return .device(address, .off)
    case "status":
      try expectNoArguments(rest, subcommand: "device")
      return .device(address, .status)
    case "links":
      try expectNoArguments(rest, subcommand: "device")
      return .device(address, .links)
    default:
      if action.hasPrefix("-") {

        throw ArgumentError.unknownOption(split(action).name, subcommand: "device")

      }

      throw ArgumentError.unknownDeviceAction(action)
    }

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

  /// A whole number of seconds, from 1 to 3,600.
  private static func seconds(_ text: String, option: String) throws(ArgumentError) -> Int {

    guard let seconds = Int(text), (1...3_600).contains(seconds) else {

      throw ArgumentError.invalidValue(option: option, value: text, expected: "a number of seconds from 1 to 3600")

    }

    return seconds

  }

  /// A level from 0 to 100 percent, with or without a percent sign.
  private static func percent(_ text: String) throws(ArgumentError) -> Int {

    let digits = text.hasSuffix("%") ? String(text.dropLast()) : text

    guard let percent = Int(digits), (0...100).contains(percent) else {

      throw ArgumentError.invalidValue(option: "on", value: text, expected: "a level from 0 to 100, such as 50%")

    }

    return percent

  }

}
