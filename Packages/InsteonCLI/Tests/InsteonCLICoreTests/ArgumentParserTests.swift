import Testing
import InsteonCLICore
import InsteonCore
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

    #expect(invocation == Invocation(serialPath: "/dev/ttyUSB0", printsJSON: true, subcommand: .links(LinksOptions())))

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

  @Test func stopsAtTheFirstHubUnlessAskedForAll() throws {

    #expect(DiscoverOptions().searchesAllAddresses == false)
    #expect(
      try Invocation.parse(["discover", "--all"]).subcommand
        == .discover(DiscoverOptions(searchesLocalNetwork: true, searchesAllAddresses: true))
    )

  }

  // Sending the password to each Hub found is opt-in.
  @Test func identifiesHubsOnlyWhenAsked() throws {

    #expect(DiscoverOptions().identifiesHubs == false)
    #expect(
      try Invocation.parse(["discover", "--insteon-connect", "--identify"]).subcommand
        == .discover(DiscoverOptions(searchesLocalNetwork: false, asksInsteonConnect: true, identifiesHubs: true))
    )

  }

  @Test func identifiesOneHubByItsAddress() throws {

    let withPort = try Invocation.parse(["discover", "--identify", "192.168.1.20:25105"])
    let target = HubAddress(host: "192.168.1.20", port: 25105)
    let expected = DiscoverOptions(identifiesHubs: true, identifyTarget: target)

    #expect(withPort.subcommand == .discover(expected))

    let inline = try Invocation.parse(["discover", "--identify=192.168.1.20:25105"])

    #expect(inline.subcommand == .discover(expected))

    let hostOnly = try Invocation.parse(["discover", "--identify", "192.168.1.20", "--all"])
    let hostOnlyOptions = DiscoverOptions(searchesAllAddresses: true, identifiesHubs: true, identifyTarget: HubAddress(host: "192.168.1.20"))

    #expect(hostOnly.subcommand == .discover(hostOnlyOptions))

  }

  @Test func identifiesWithoutATargetBeforeAnotherOption() throws {

    let invocation = try Invocation.parse(["discover", "--identify", "--all"])
    let expected = DiscoverOptions(searchesAllAddresses: true, identifiesHubs: true)

    #expect(invocation.subcommand == .discover(expected))

  }

  @Test func rejectsAMalformedIdentifyTarget() {

    #expect(throws: ArgumentError.missingValue(option: "--identify")) {

      try Invocation.parse(["discover", "--identify="])

    }

    let expected = "HOST or HOST:PORT, such as 192.168.1.20"

    #expect(throws: ArgumentError.invalidValue(option: "--identify", value: "192.168.1.20:0", expected: expected)) {

      try Invocation.parse(["discover", "--identify", "192.168.1.20:0"])

    }

    #expect(throws: ArgumentError.invalidValue(option: "--identify", value: ":25105", expected: expected)) {

      try Invocation.parse(["discover", "--identify=:25105"])

    }

    #expect(throws: ArgumentError.unexpectedArgument("192.168.1.21", subcommand: "discover")) {

      try Invocation.parse(["discover", "--identify", "192.168.1.20", "192.168.1.21"])

    }

  }

  // The password isn't repeated in the error.
  @Test func refusesCredentialsInTheIdentifyTarget() {

    #expect(throws: ArgumentError.credentialsInOption("--identify")) {

      try Invocation.parse(["discover", "--identify", "example-user:example-password@192.168.1.20"])

    }

    #expect(!ArgumentError.credentialsInOption("--identify").description.contains("example-password"))

  }

  // MARK: - links

  @Test func identifiesLinkedDevicesOnlyWhenAsked() throws {

    #expect(try Invocation.parse(["links"]).subcommand == .links(LinksOptions(identifiesDevices: false)))
    #expect(try Invocation.parse(["links", "--identify"]).subcommand == .links(LinksOptions(identifiesDevices: true)))

    #expect(throws: ArgumentError.unexpectedArgument("all", subcommand: "links")) {

      try Invocation.parse(["links", "all"])

    }

  }

  // MARK: - link and unlink

  // Insteon's Hub app, and the catalog's From a Hub procedures, link devices in group 0.
  @Test func linksAsTheControllerOfGroup0ByDefault() throws {

    #expect(try Invocation.parse(["link"]).subcommand == .link(LinkOptions(group: 0, role: .controller, timeoutSeconds: nil)))

  }

  // Without --group, unlink reads the modem's records for the device's group, since links
  // made before group 0 was the default are in group 1.
  @Test func unlinksTheRecordedGroupUnlessOneIsGiven() throws {

    #expect(UnlinkOptions().group == nil)
    #expect(try Invocation.parse(["unlink", "1A.2B.3C"]).subcommand == .unlink(UnlinkOptions(device: lamp, group: nil)))
    #expect(try Invocation.parse(["unlink", "1A.2B.3C", "--group", "0"]).subcommand == .unlink(UnlinkOptions(device: lamp, group: 0)))

  }

  @Test func linksADeviceByItsAddress() throws {

    #expect(try Invocation.parse(["link", "1A.2B.3C"]).subcommand == .link(LinkOptions(device: lamp)))
    #expect(
      try Invocation.parse(["link", "--two-way", "1a2b3c", "--group", "2"]).subcommand
        == .link(LinkOptions(device: lamp, group: 2, twoWay: .always))
    )
    #expect(try Invocation.parse(["link", "--two-way"]).subcommand == .link(LinkOptions(twoWay: .always)))
    #expect(try Invocation.parse(["unlink", "1A.2B.3C", "--responder"]).subcommand == .unlink(UnlinkOptions(device: lamp, role: .responder)))

  }

  @Test func rejectsAMalformedOrSecondAddress() {

    #expect(throws: ArgumentError.invalidAddress("1A.2B")) {

      try Invocation.parse(["link", "1A.2B"])

    }

    #expect(throws: ArgumentError.unexpectedArgument("4D.5E.6F", subcommand: "unlink")) {

      try Invocation.parse(["unlink", "1A.2B.3C", "4D.5E.6F"])

    }

  }

  @Test func linksBackWhenTheDeviceControlsUnlessOneWay() throws {

    #expect(LinkOptions().twoWay == .whenDeviceControls)
    #expect(try Invocation.parse(["link"]).subcommand == .link(LinkOptions(twoWay: .whenDeviceControls)))
    #expect(try Invocation.parse(["link", "1A.2B.3C"]).subcommand == .link(LinkOptions(device: lamp, twoWay: .whenDeviceControls)))
    #expect(try Invocation.parse(["link", "--one-way"]).subcommand == .link(LinkOptions(twoWay: .never)))
    #expect(try Invocation.parse(["link", "1A.2B.3C", "--one-way"]).subcommand == .link(LinkOptions(device: lamp, twoWay: .never)))
    #expect(try Invocation.parse(["link", "--responder", "--one-way"]).subcommand == .link(LinkOptions(role: .responder, twoWay: .never)))
    #expect(try Invocation.parse(["link", "--two-way", "--two-way"]).subcommand == .link(LinkOptions(twoWay: .always)))

  }

  @Test func rejectsOneWayWithTwoWay() {

    #expect(throws: ArgumentError.conflictingOptions("--one-way", "--two-way")) {

      try Invocation.parse(["link", "--one-way", "--two-way"])

    }

    #expect(throws: ArgumentError.conflictingOptions("--two-way", "--one-way")) {

      try Invocation.parse(["link", "1A.2B.3C", "--two-way", "--one-way"])

    }

    #expect(throws: ArgumentError.conflictingOptions("--cancel", "--one-way")) {

      try Invocation.parse(["link", "--one-way", "--cancel"])

    }

  }

  @Test func rejectsTwoWayWithAnotherRole() {

    #expect(throws: ArgumentError.conflictingOptions("--two-way", "--responder")) {

      try Invocation.parse(["link", "--responder", "--two-way"])

    }

    #expect(throws: ArgumentError.conflictingOptions("--either", "1A.2B.3C")) {

      try Invocation.parse(["link", "1A.2B.3C", "--either"])

    }

    #expect(throws: ArgumentError.conflictingOptions("--cancel", "1A.2B.3C")) {

      try Invocation.parse(["link", "1A.2B.3C", "--cancel"])

    }

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
  @Test func rejectsGroup255() throws {

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

  @Test func unlinksEveryLinkWithADeviceWithAll() throws {

    let all = UnlinkOptions(device: lamp, removesAllLinks: true)
    let timed = UnlinkOptions(device: lamp, timeoutSeconds: 10, removesAllLinks: true)

    #expect(UnlinkOptions().removesAllLinks == false)
    #expect(try Invocation.parse(["unlink", "1A.2B.3C", "--all"]).subcommand == .unlink(all))
    #expect(try Invocation.parse(["unlink", "--all", "1A.2B.3C", "--timeout", "10"]).subcommand == .unlink(timed))

  }

  @Test func needsADeviceAndNoGroupOrRoleWithAll() throws {

    #expect(throws: ArgumentError.missingArgument("ADDRESS with --all", subcommand: "unlink")) {

      try Invocation.parse(["unlink", "--all"])

    }

    #expect(throws: ArgumentError.conflictingOptions("--all", "--group")) {

      try Invocation.parse(["unlink", "1A.2B.3C", "--all", "--group", "1"])

    }

    #expect(throws: ArgumentError.conflictingOptions("--all", "--responder")) {

      try Invocation.parse(["unlink", "1A.2B.3C", "--responder", "--all"])

    }

    #expect(throws: ArgumentError.unexpectedValue(option: "--all")) {

      try Invocation.parse(["unlink", "1A.2B.3C", "--all=yes"])

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

  // MARK: - catalog

  @Test func readsCatalog() throws {

    #expect(try Invocation.parse(["catalog"]).subcommand == .catalog)
    #expect(try Invocation.parse(["catalog", "update"]).subcommand == .catalogUpdate)

    // The command's own options are still read, though the catalog commands use none of them.
    #expect(try Invocation.parse(["--hub", "192.168.1.20", "catalog", "update"]) == Invocation(hub: "192.168.1.20", subcommand: .catalogUpdate))

  }

  @Test func printsCatalogsHelp() throws {

    #expect(try Invocation.parse(["catalog", "--help"]).subcommand == .help(topic: "catalog"))
    #expect(try Invocation.parse(["catalog", "update", "--help"]).subcommand == .help(topic: "catalog"))
    #expect(try Invocation.parse(["help", "catalog"]).subcommand == .help(topic: "catalog"))
    #expect(HelpText.text(for: "catalog") == HelpText.catalog)

  }

  @Test func rejectsOtherCatalogArguments() {

    #expect(throws: ArgumentError.unexpectedArgument("download", subcommand: "catalog")) {

      try Invocation.parse(["catalog", "download"])

    }

    #expect(throws: ArgumentError.unexpectedArgument("now", subcommand: "catalog")) {

      try Invocation.parse(["catalog", "update", "now"])

    }

    #expect(throws: ArgumentError.unknownOption("--force", subcommand: "catalog")) {

      try Invocation.parse(["catalog", "update", "--force"])

    }

  }

  // MARK: - remove

  @Test func removesADeviceByItsAddress() throws {

    #expect(try Invocation.parse(["remove", "1A.2B.3C"]).subcommand == .remove(RemoveOptions(device: lamp)))
    #expect(
      try Invocation.parse(["remove", "--scan", "1A.2B.3C", "--force-modem-side", "--yes", "--timeout", "10"]).subcommand
        == .remove(RemoveOptions(device: lamp, scansOtherDevices: true, forcesModemSide: true, assumesYes: true, timeoutSeconds: 10))
    )
    #expect(try Invocation.parse(["remove", "1A.2B.3C", "-y"]).subcommand == .remove(RemoveOptions(device: lamp, assumesYes: true)))
    #expect(try Invocation.parse(["--json", "remove", "1A.2B.3C"]).printsJSON)

  }

  @Test func needsOneAddressToRemove() {

    #expect(throws: ArgumentError.missingArgument("a device's ADDRESS, such as 1A.2B.3C", subcommand: "remove")) {

      try Invocation.parse(["remove", "--scan"])

    }

    #expect(throws: ArgumentError.unexpectedArgument("4E.5F.01", subcommand: "remove")) {

      try Invocation.parse(["remove", "1A.2B.3C", "4E.5F.01"])

    }

    #expect(throws: ArgumentError.unknownOption("--all", subcommand: "remove")) {

      try Invocation.parse(["remove", "1A.2B.3C", "--all"])

    }

    #expect(throws: ArgumentError.unexpectedValue(option: "--yes")) {

      try Invocation.parse(["remove", "1A.2B.3C", "--yes=no"])

    }

  }

  @Test func printsRemovesHelp() throws {

    #expect(try Invocation.parse(["remove", "--help"]).subcommand == .help(topic: "remove"))
    #expect(HelpText.text(for: "remove") == HelpText.remove)
    #expect(HelpText.overview.contains("remove ADDRESS"))

  }

  @Test func asksBeforeRemovingAtATerminalUnlessToldYes() throws {

    let asking = RemoveOptions(device: lamp)
    let yes = RemoveOptions(device: lamp, assumesYes: true)

    #expect(try asking.asksForConfirmation(readsFromTerminal: true))
    #expect(try !yes.asksForConfirmation(readsFromTerminal: true))
    #expect(try !yes.asksForConfirmation(readsFromTerminal: false))

  }

  @Test func needsYesToRemoveWithoutATerminal() {

    #expect(throws: ArgumentError.confirmationNeeded(subcommand: "remove")) {

      try RemoveOptions(device: lamp).asksForConfirmation(readsFromTerminal: false)

    }

    #expect(ArgumentError.confirmationNeeded(subcommand: "remove").description.contains("--yes"))

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
      .credentialsInHub,
      .confirmationNeeded(subcommand: "remove")
    ]

    for error in errors {

      #expect(!error.description.isEmpty)
      #expect(!error.description.contains("\n"))

    }

  }

  @Test func followsTheCatalogsLegsOnlyWithoutARoleOrGroupOfItsOwn() throws {

    func options(_ arguments: [String]) throws -> LinkOptions? {

      guard case let .link(options) = try Invocation.parse(arguments).subcommand else {

        return nil

      }

      return options

    }

    #expect(try options(["link", "1A.2B.3C"])?.followsCatalogLegs == true)
    // --either takes no address: it links whichever device has its SET button pressed.
    #expect(throws: ArgumentError.conflictingOptions("--either", "1A.2B.3C")) {

      try Invocation.parse(["link", "1A.2B.3C", "--either"])

    }
    #expect(try options(["link", "1A.2B.3C", "--responder"])?.followsCatalogLegs == false)
    // Group 0 given explicitly is a group of its own, though it's the default.
    #expect(try options(["link", "1A.2B.3C", "--group", "0"])?.followsCatalogLegs == false)
    #expect(try options(["link", "1A.2B.3C", "--group", "0"]) == LinkOptions(device: InsteonAddress(0x1A, 0x2B, 0x3C), isGroupGiven: true))

  }

}
