import Testing
import InsteonCLICore
import InsteonProtocol

struct ArgumentParserTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  // MARK: - The command's own options

  @Test func printsTheOverviewWithNoArguments() throws {

    #expect(try Invocation.parse([]) == Invocation(subcommand: .help(topic: nil)))

  }

  @Test func readsTheHubBeforeOrAfterTheSubcommand() throws {

    let before = try Invocation.parse(["--hub", "192.168.1.20", "info"])
    let after = try Invocation.parse(["info", "--hub=192.168.1.20"])

    #expect(before == Invocation(hub: "192.168.1.20", subcommand: .info))
    #expect(after == before)

  }

  @Test func readsTheSerialPortAndJSON() throws {

    let invocation = try Invocation.parse(["--serial", "/dev/ttyUSB0", "--json", "links"])

    #expect(invocation == Invocation(serialPath: "/dev/ttyUSB0", printsJSON: true, subcommand: .links))

  }

  @Test func needsAValueForTheHub() {

    #expect(throws: ArgumentError.missingValue(option: "--hub")) {

      try Invocation.parse(["info", "--hub"])

    }

    #expect(throws: ArgumentError.missingValue(option: "--hub")) {

      try Invocation.parse(["--hub", "--json", "info"])

    }

    #expect(throws: ArgumentError.missingValue(option: "--hub")) {

      try Invocation.parse(["--hub=", "info"])

    }

  }

  // Credentials come only from the environment, so an option for them is unknown, and its
  // value isn't repeated in the error.
  @Test func refusesCredentialsOnTheCommandLine() {

    #expect(throws: ArgumentError.unknownOption("--password", subcommand: nil)) {

      try Invocation.parse(["--password=example-password", "info"])

    }

    #expect(throws: ArgumentError.unknownOption("--user", subcommand: "info")) {

      try Invocation.parse(["info", "--user=example-user"])

    }

  }

  // A value that might be a password isn't repeated in the error.
  @Test func doesntRepeatAnOptionsValue() {

    #expect(throws: ArgumentError.unknownOption("--password", subcommand: "device")) {

      try Invocation.parse(["device", "1A.2B.3C", "on", "--password=example-password"])

    }

    #expect(throws: ArgumentError.unknownOption("--x", subcommand: nil)) {

      try Invocation.parse(["help", "--x=example-secret"])

    }

    #expect(throws: ArgumentError.credentialsInHub) {

      try Invocation.parse(["--hub", "example-user:example-password@192.168.1.20", "info"])

    }

    #expect(!ArgumentError.credentialsInHub.description.contains("example-password"))

  }

  @Test func readsTheEnvironmentFile() throws {

    let invocation = try Invocation.parse(["--env-file", "/tmp/example/env", "info"])

    #expect(invocation == Invocation(envFilePath: "/tmp/example/env", subcommand: .info))
    #expect(try Invocation.parse(["info", "--env-file=/tmp/example/env"]) == invocation)

  }

  @Test func rejectsAnUnknownCommand() {

    #expect(throws: ArgumentError.unknownCommand("dance")) {

      try Invocation.parse(["dance"])

    }

  }

  // MARK: - Help

  @Test func printsASubcommandsHelp() throws {

    #expect(try Invocation.parse(["link", "--help"]).subcommand == .help(topic: "link"))
    #expect(try Invocation.parse(["-h", "device"]).subcommand == .help(topic: "device"))
    #expect(try Invocation.parse(["help", "watch"]).subcommand == .help(topic: "watch"))
    #expect(try Invocation.parse(["--help"]).subcommand == .help(topic: nil))

  }

  @Test func rejectsHelpForSomethingThatIsntASubcommand() {

    #expect(throws: ArgumentError.unknownHelpTopic("dance")) {

      try Invocation.parse(["help", "dance"])

    }

  }

  @Test func hasHelpForEverySubcommand() {

    for name in Invocation.subcommandNames {

      #expect(HelpText.text(for: name) != nil)

    }

    #expect(HelpText.text(for: nil) == HelpText.overview)
    #expect(HelpText.text(for: "dance") == nil)

  }

  // MARK: - discover

  // Insteon Connect sees the network's public IP address, so it's asked only when asked for.
  @Test func discoversOnTheLocalNetworkByDefault() throws {

    #expect(try Invocation.parse(["discover"]).subcommand == .discover(DiscoverOptions()))
    #expect(DiscoverOptions() == DiscoverOptions(searchesLocalNetwork: true, asksInsteonConnect: false))
    #expect(
      try Invocation.parse(["discover", "--local", "--insteon-connect"]).subcommand
        == .discover(DiscoverOptions(searchesLocalNetwork: true, asksInsteonConnect: true))
    )

  }

  @Test func discoversOneWay() throws {

    #expect(
      try Invocation.parse(["discover", "--local"]).subcommand
        == .discover(DiscoverOptions(searchesLocalNetwork: true, asksInsteonConnect: false))
    )
    #expect(
      try Invocation.parse(["discover", "--insteon-connect"]).subcommand
        == .discover(DiscoverOptions(searchesLocalNetwork: false, asksInsteonConnect: true))
    )

  }

  // MARK: - link and unlink

  @Test func linksAsTheControllerOfGroup1ByDefault() throws {

    #expect(try Invocation.parse(["link"]).subcommand == .link(LinkOptions(group: 1, role: .controller, timeoutSeconds: nil)))

  }

  @Test func readsTheLinkingOptions() throws {

    let invocation = try Invocation.parse(["link", "--group", "5", "--responder", "--timeout=60"])

    #expect(invocation.subcommand == .link(LinkOptions(group: 5, role: .responder, timeoutSeconds: 60)))
    #expect(try Invocation.parse(["link", "--either"]).subcommand == .link(LinkOptions(role: .either)))

  }

  @Test func rejectsTwoRoles() {

    #expect(throws: ArgumentError.conflictingOptions("--controller", "--responder")) {

      try Invocation.parse(["link", "--controller", "--responder"])

    }

  }

  @Test func rejectsAGroupOutsideAByte() {

    #expect(throws: ArgumentError.invalidValue(option: "--group", value: "256", expected: "a group number from 0 to 254")) {

      try Invocation.parse(["link", "--group", "256"])

    }

  }

  // Group 255 means every group.
  @Test func rejectsGroup255() {

    #expect(throws: ArgumentError.invalidValue(option: "--group", value: "255", expected: "a group number from 0 to 254")) {

      try Invocation.parse(["link", "--group", "255"])

    }

    #expect(throws: ArgumentError.invalidValue(option: "--group", value: "255", expected: "a group number from 0 to 254")) {

      try Invocation.parse(["unlink", "--group=255"])

    }

    #expect(try Invocation.parse(["link", "--group", "254"]).subcommand == .link(LinkOptions(group: 254)))

  }

  @Test func rejectsATimeoutOfZero() {

    #expect(throws: ArgumentError.invalidValue(option: "--timeout", value: "0", expected: "a number of seconds from 1 to 3600")) {

      try Invocation.parse(["unlink", "--timeout", "0"])

    }

  }

  @Test func cancelsLinking() throws {

    #expect(try Invocation.parse(["link", "--cancel"]).subcommand == .cancelLinking)

  }

  @Test func rejectsCancelWithOtherOptions() {

    #expect(throws: ArgumentError.conflictingOptions("--cancel", "--group")) {

      try Invocation.parse(["link", "--group", "2", "--cancel"])

    }

    #expect(throws: ArgumentError.conflictingOptions("--cancel", "--responder")) {

      try Invocation.parse(["link", "--cancel", "--responder"])

    }

  }

  @Test func unlinksInEitherRoleButNotBoth() throws {

    #expect(try Invocation.parse(["unlink"]).subcommand == .unlink(UnlinkOptions()))
    #expect(
      try Invocation.parse(["unlink", "--group", "3", "--responder"]).subcommand
        == .unlink(UnlinkOptions(group: 3, role: .responder))
    )

    #expect(throws: ArgumentError.unknownOption("--either", subcommand: "unlink")) {

      try Invocation.parse(["unlink", "--either"])

    }

  }

  // MARK: - device

  @Test func readsADevicesAddressAndAction() throws {

    #expect(try Invocation.parse(["device", "1A.2B.3C", "id"]).subcommand == .device(lamp, .id))
    #expect(try Invocation.parse(["device", "1a2b3c", "ping"]).subcommand == .device(lamp, .ping))
    #expect(try Invocation.parse(["device", "1A.2B.3C", "off"]).subcommand == .device(lamp, .off))
    #expect(try Invocation.parse(["device", "1A.2B.3C", "status"]).subcommand == .device(lamp, .status))
    #expect(try Invocation.parse(["device", "1A.2B.3C", "links"]).subcommand == .device(lamp, .links))

  }

  @Test func turnsOnFullyOrToALevel() throws {

    #expect(try Invocation.parse(["device", "1A.2B.3C", "on"]).subcommand == .device(lamp, .on(levelPercent: nil)))
    #expect(try Invocation.parse(["device", "1A.2B.3C", "on", "50%"]).subcommand == .device(lamp, .on(levelPercent: 50)))
    #expect(try Invocation.parse(["device", "1A.2B.3C", "on", "100"]).subcommand == .device(lamp, .on(levelPercent: 100)))
    #expect(try Invocation.parse(["device", "1A.2B.3C", "on", "0"]).subcommand == .device(lamp, .on(levelPercent: 0)))

  }

  @Test func rejectsALevelAbove100() {

    #expect(throws: ArgumentError.invalidValue(option: "on", value: "101%", expected: "a level from 0 to 100, such as 50%")) {

      try Invocation.parse(["device", "1A.2B.3C", "on", "101%"])

    }

    #expect(throws: ArgumentError.unknownOption("-5", subcommand: "device")) {

      try Invocation.parse(["device", "1A.2B.3C", "on", "-5"])

    }

  }

  @Test func rejectsAMalformedDeviceCommand() {

    #expect(throws: ArgumentError.missingAddress) {

      try Invocation.parse(["device"])

    }

    #expect(throws: ArgumentError.invalidAddress("1A.2B")) {

      try Invocation.parse(["device", "1A.2B", "on"])

    }

    #expect(throws: ArgumentError.missingDeviceAction) {

      try Invocation.parse(["device", "1A.2B.3C"])

    }

    #expect(throws: ArgumentError.unknownDeviceAction("dim")) {

      try Invocation.parse(["device", "1A.2B.3C", "dim"])

    }

    #expect(throws: ArgumentError.unexpectedArgument("now", subcommand: "device")) {

      try Invocation.parse(["device", "1A.2B.3C", "off", "now"])

    }

  }

  // MARK: - watch

  @Test func watchesWithOrWithoutRawReplies() throws {

    #expect(try Invocation.parse(["watch"]).subcommand == .watch(WatchOptions()))
    #expect(try Invocation.parse(["watch", "--raw"]).subcommand == .watch(WatchOptions(printsRawReplies: true)))

  }

  // MARK: - Messages

  @Test func explainsErrorsInOneLine() {

    let errors: [ArgumentError] = [
      .unknownCommand("dance"),
      .unknownOption("--user", subcommand: "info"),
      .missingValue(option: "--hub"),
      .conflictingOptions("--controller", "--responder"),
      .invalidAddress("1A.2B"),
      .missingDeviceAction,
      .credentialsInHub
    ]

    for error in errors {

      #expect(!error.description.isEmpty)
      #expect(!error.description.contains("\n"))

    }

  }

}
