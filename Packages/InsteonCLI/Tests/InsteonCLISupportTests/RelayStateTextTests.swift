import Foundation
import Testing
@testable import InsteonCLISupport
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// Parsing `link --relay-state`, and what `insteon link` prints while it puts a relay in the
/// state and after it links.
struct RelayStateTextTests {

  let module = InsteonAddress(0x1A, 0x2B, 0x3C)

  let modem = InsteonAddress(0x11, 0x22, 0x33)

  struct Failure: Error {}

  /// A made-up flag that keeps the relay from holding a state.
  let pulse = RelayFlag(name: "pulse", label: "Pulse")

  /// A made-up flag that, with pulse, makes every On and Off only pulse the relay.
  let pulseBoth = RelayFlag(name: "pulseBoth", label: "Pulse on both")

  /// How the made-up relay holds a state, with the flags given on.
  func holding(_ flagsOn: [RelayFlag] = [], restState: RelayState = .off) -> RelayStateHolding {

    RelayStateHolding(releasedBy: ["pulse"], restState: restState, pulsesOnEveryCommandWhen: [["pulse", "pulseBoth"]], flagsOn: flagsOn)

  }

  func notes(_ event: LinkingEvent) -> [String] {

    LinkingEventText.notes(for: event, message: { (_: any Error) -> String in "It failed." })

  }

  // MARK: - Parsing

  @Test func linksWithARelayState() throws {

    let on = try Invocation.parse(["link", "1A.2B.3C", "--group", "2", "--relay-state", "on"]).subcommand
    let off = try Invocation.parse(["link", "1A.2B.3C", "--relay-state=off"]).subcommand
    let database = try Invocation.parse(["link", "1A.2B.3C", "--database", "--dry-run", "--relay-state", "on"]).subcommand

    #expect(on == .link(LinkOptions(device: module, group: 2, relayState: .on, relayStateConfirmation: DatabaseWriteOptions())))
    #expect(off == .link(LinkOptions(device: module, relayState: .off, relayStateConfirmation: DatabaseWriteOptions())))
    #expect(database == .link(LinkOptions(device: module, database: DatabaseWriteOptions(isDryRun: true), relayState: .on)))

  }

  @Test func asksBeforeSwitchingTheRelayUnlessADryRunOrYes() throws {

    let yes = try Invocation.parse(["link", "1A.2B.3C", "--relay-state", "on", "--yes"]).subcommand
    let dry = try Invocation.parse(["link", "1A.2B.3C", "--relay-state", "on", "--dry-run"]).subcommand

    #expect(yes == .link(LinkOptions(device: module, relayState: .on, relayStateConfirmation: DatabaseWriteOptions(assumesYes: true))))
    #expect(dry == .link(LinkOptions(device: module, relayState: .on, relayStateConfirmation: DatabaseWriteOptions(isDryRun: true))))
    #expect(try DatabaseWriteOptions().asksForConfirmation(readsFromTerminal: true, subcommand: "link"))
    #expect(throws: ArgumentError.confirmationNeeded(subcommand: "link")) {

      try DatabaseWriteOptions().asksForConfirmation(readsFromTerminal: false, subcommand: "link")

    }

  }

  // MARK: - The plan

  func plan(before: RelayState = .off, pulsing: Bool = false, both: Bool = false, state: RelayState = .on) -> RelayLinkPlan {

    RelayLinkPlan(device: module, state: state, before: before, holding: holding((pulsing ? [pulse] : []) + (both ? [pulseBoth] : [])))

  }

  @Test func showsWhatTheLinkWillSwitchAndPutBack() {

    #expect(RelayLinkText.plan(plan(pulsing: true)) == [
      "Linking 1A.2B.3C so a group On turns its relay on and a group Off turns it off:",
      "  1. Turn its Pulse flag off for the link, so the relay holds its state.",
      "  2. Turn the relay on. Whatever it controls, such as a garage door opener, a lock or a valve, acts on it.",
      "  3. Link it, then turn the relay off again, since it returns to off by itself with that flag on, and turn its Pulse flag back on."
    ])
    #expect(RelayLinkText.plan(plan()) == [
      "Linking 1A.2B.3C so a group On turns its relay on and a group Off turns it off:",
      "  1. Turn the relay on. Whatever it controls, such as a garage door opener, a lock or a valve, acts on it.",
      "  2. Link it. The relay stays on, and is turned back off if linking fails or is stopped."
    ])
    #expect(RelayLinkText.plan(plan(before: .on)) == [
      "Linking 1A.2B.3C so a group On turns its relay on and a group Off turns it off:",
      "  1. Link it. The relay is already on, so it isn't switched."
    ])
    #expect(RelayLinkText.plan(plan(pulsing: true, both: true)) == [
      "1A.2B.3C's Pulse and Pulse on both flags are on, so every On and Off only pulses its relay and the state is ignored.",
      "  1. Link it. The relay isn't switched and no flag is written."
    ])
    // A flag set that isn't the catalog's pulsing set is an ordinary relay.
    #expect(RelayLinkText.plan(plan(both: true)) == RelayLinkText.plan(plan()))
    // A relay that rests on returns to on.
    let restsOn = RelayLinkPlan(device: module, state: .off, before: .on, holding: holding([pulse], restState: .on))
    #expect(RelayLinkText.plan(restsOn).last == "  3. Link it, then turn the relay on again, since it returns to on by itself with that flag on, and turn its Pulse flag back on.")

  }

  @Test func showsThatARelayReadOutOfItsRestStateIsSwitchedToItWithoutAFlag() {

    // Read on mid-pulse, a relay that rests off is switched off and stays there by itself.
    let midPulse: RelayLinkPlan = plan(before: .on, pulsing: true, state: .off)

    #expect(RelayLinkText.plan(midPulse) == [
      "Linking 1A.2B.3C so a group On turns its relay off and a group Off turns it on:",
      "  1. Turn the relay off. Whatever it controls, such as a garage door opener, a lock or a valve, acts on it.",
      "  2. Link it. The relay stays off by itself, its rest state, so no flag is written."
    ])
    #expect(RelayLinkText.question(midPulse) == "Switch 1A.2B.3C's relay off and link it? [y/N]")

  }

  @Test(.timeLimit(.minutes(1))) func decidesWhetherToShowOnlyAskOrLink() async throws {

    let confirms = { (_: String) async throws -> Bool in true }
    let declines = { (_: String) async throws -> Bool in false }

    #expect(try await RelayLinkText.decision(plan(), isDryRun: true, asks: true, confirm: confirms) == .dryRun)
    #expect(try await RelayLinkText.decision(plan(), isDryRun: false, asks: true, confirm: declines) == .declined)
    #expect(try await RelayLinkText.decision(plan(), isDryRun: false, asks: true, confirm: confirms) == .link)
    #expect(try await RelayLinkText.decision(plan(), isDryRun: false, asks: false, confirm: declines) == .link)
    // A plan that switches nothing isn't asked about.
    #expect(try await RelayLinkText.decision(plan(before: .on), isDryRun: false, asks: true, confirm: declines) == .link)

  }

  @Test func keepsTheGroupInTheGuidanceToPlanAgain() {

    let old: RelayLinkPlan = plan()
    var new: RelayLinkPlan = old

    new.before = .on

    let error = RelayStateLinkingError.planChanged(old: old, new: new)

    #expect(LinkingEventText.relayStateMessage(error, group: 2) == error.description
      + " Run 'insteon link 1A.2B.3C --group 2 --relay-state on' again to see the plan as it is.")
    #expect(LinkingEventText.relayStateMessage(error) == error.description
      + " Run 'insteon link 1A.2B.3C --relay-state on' again to see the plan as it is.")

  }

  @Test func doesntClaimAStateTheRelayIgnores() throws {

    let ignored = RelayStateLink(device: module, state: .on, group: 2, recordedData1: 0x00, holding: holding([pulse, pulseBoth]))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let report = LinkingJSON.report(DeviceLinkingResult(links: [], device: nil, linkBackFailure: nil, relayState: ignored), message: { (_: any Error) -> String in "" })

    #expect(String(decoding: try encoder.encode(report.relayState), as: UTF8.self) == """
      {"holdsState":false,"ignoresState":true,"recordedData1":"0x00","releasingFlags":["pulse"],"state":"on"}
      """)
    #expect(notes(.relayState(.recorded(ignored))) == [
      "1A.2B.3C linked without switching its relay, whose record holds Data 1 0x00. "
        + "Its Pulse and Pulse on both flags are on, so every On and Off only pulses it and the state is ignored."
    ])

  }

  @Test func saysWhyTheRecordOfARelayThatIgnoresTheStateIsntShown() {

    var notFound = RelayStateLink(device: module, state: .on, group: 2, recordedData1: nil, holding: holding([pulse, pulseBoth]))
    var notRead: RelayStateLink = notFound

    notFound.recordFailure = .recordNotFound(module, group: 2)
    notRead.recordFailure = .recordNotRead(module, reason: Failure())

    let mode: String = "Its Pulse and Pulse on both flags are on, so every On and Off only pulses it and the state is ignored."

    #expect(notes(.relayState(.recorded(notFound))) == ["1A.2B.3C linked without switching its relay, whose record wasn't found. " + mode])
    #expect(notes(.relayState(.recorded(notRead))) == ["1A.2B.3C linked without switching its relay, whose record wasn't read. " + mode])

  }

  @Test func describesTheJSONInTheHelp() {

    #expect(HelpText.link.contains("\"relayState\""))
    #expect(HelpText.link.contains("absent when the state is ignored"))
    #expect(HelpText.link.contains("the plan as an object"))

  }

  @Test func printsThePlanAsJSONForADryRun() throws {

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    #expect(String(decoding: try encoder.encode(RelayLinkText.report(plan(pulsing: true), isDryRun: true)), as: UTF8.self) == """
      {"before":"off","clearedFlags":["pulse"],"device":"1A.2B.3C","dryRun":true,"flagsOn":["pulse"],"ignoresState":false,"pulsingFlags":[],\
      "releasingFlags":["pulse"],"restState":"off","returnsToRestAfterLinking":true,"state":"on","switchesBackOnFailure":false,"switchesRelay":true}
      """)

  }

  @Test func asksOnlyWhenTheRelayIsSwitched() {

    #expect(RelayLinkText.question(plan()) == "Switch 1A.2B.3C's relay on and link it? [y/N]")
    #expect(RelayLinkText.question(plan(pulsing: true)) == "Turn off 1A.2B.3C's Pulse flag, switch its relay on and link it? [y/N]")
    #expect(RelayLinkText.question(plan(before: .on)) == nil)
    #expect(RelayLinkText.question(plan(pulsing: true, both: true)) == nil)
    #expect(RelayLinkText.declined == "Nothing was switched or linked.")
    #expect(RelayLinkText.dryRun == "Dry run: nothing was switched or linked.")

  }

  @Test func refusesARelayStateThatIsntOnOrOff() {

    #expect(throws: ArgumentError.invalidValue(option: "--relay-state", value: "closed", expected: "on or off")) {

      try Invocation.parse(["link", "1A.2B.3C", "--relay-state", "closed"])

    }

    #expect(throws: ArgumentError.missingValue(option: "--relay-state")) {

      try Invocation.parse(["link", "1A.2B.3C", "--relay-state"])

    }

  }

  @Test func refusesARelayStateWithoutADeviceOrWithTheModemResponding() {

    #expect(throws: ArgumentError.missingArgument("ADDRESS with --relay-state", subcommand: "link")) {

      try Invocation.parse(["link", "--relay-state", "on"])

    }

    for option in ["--responder", "--either", "--cancel"] {

      #expect(throws: ArgumentError.conflictingOptions("--relay-state", option)) {

        try Invocation.parse(["link", "1A.2B.3C", "--relay-state", "on", option])

      }

    }

  }

  @Test func describesTheOptionInTheHelp() {

    #expect(HelpText.link.contains("--relay-state on|off"))
    #expect(HelpText.link.contains("switches the relay, and whatever it controls"))

  }

  // MARK: - What's printed

  func link(_ state: RelayState = .on, pulsing: Bool = false, both: Bool = false, record: RelayStateLinkingError? = nil, restore: [RelayStateLinkingError] = []) -> RelayStateLink {

    RelayStateLink(
      device: module,
      state: state,
      group: 2,
      recordedData1: state.data1,
      recordFailure: record,
      clearedFlags: pulsing && !both ? [pulse] : [],
      holding: holding((pulsing ? [pulse] : []) + (both ? [pulseBoth] : [])),
      restoreFailures: restore
    )

  }

  @Test func saysEachStepOfPuttingTheRelayInItsState() {

    #expect(notes(.relayState(.clearingFlag(module, flag: pulse))) == [
      "Turning 1A.2B.3C's Pulse flag off for the link, so its relay holds its state..."
    ])
    #expect(notes(.relayState(.settingRelay(module, .on))) == ["Turning 1A.2B.3C's relay on, so it links with the relay on..."])
    #expect(notes(.relayState(.settingRelay(module, .off))) == ["Turning 1A.2B.3C's relay off, so it links with the relay off..."])
    #expect(notes(.relayState(.relayAlreadySet(module, .off))) == ["1A.2B.3C's relay is already off, so it links with the relay off."])
    #expect(notes(.relayState(.linkedWithoutSwitching(module, flags: [pulse, pulseBoth]))) == [
      "1A.2B.3C's Pulse and Pulse on both flags are on, so every On and Off only pulses its relay and the state is ignored. "
        + "It's linked without switching the relay or writing a flag."
    ])
    #expect(notes(.relayState(.relayLeft(module, reads: .off))) == ["1A.2B.3C's relay reads off, so it's left as it is rather than switched again."])
    #expect(notes(.relayState(.relayConfirmed(module, .on))).isEmpty)
    #expect(notes(.relayState(.returningRelay(module, .off))) == ["Turning 1A.2B.3C's relay off after the link..."])
    #expect(notes(.relayState(.restoringFlag(module, flag: pulse))) == ["Turning 1A.2B.3C's Pulse flag back on..."])
    #expect(notes(.relayState(.flagRestored(module, flag: pulse))).isEmpty)

  }

  @Test func saysWhatDidntGoBackWithTheCommandThatFixesIt() {

    let notRestored = RelayStateLinkingError.flagNotRestored(module, flag: pulse, reason: Failure())
    let unconfirmed = RelayStateLinkingError.flagRestoreUnconfirmed(module, flag: pulse, reason: Failure())
    let notReturned = RelayStateLinkingError.relayNotReturned(module, state: .off, reason: Failure())

    #expect(notes(.relayState(.restoreFailed(module, notRestored))) == [
      notRestored.description + " Turn it back on with 'insteon device 1A.2B.3C set pulse on'."
    ])
    #expect(notes(.relayState(.restoreFailed(module, unconfirmed))) == [
      unconfirmed.description + " Check it with 'insteon device 1A.2B.3C settings'."
    ])
    #expect(notes(.relayState(.restoreFailed(module, notReturned))) == [
      notReturned.description + " Turn it off with 'insteon device 1A.2B.3C off'."
    ])

  }

  @Test func guidesEachRefusalToTheCommandToRun() {

    #expect(LinkingEventText.relayStateMessage(.notLinkedToModem(module)) == RelayStateLinkingError.notLinkedToModem(module).description
      + " Link it first with 'insteon link 1A.2B.3C', then run it again with --relay-state.")
    #expect(LinkingEventText.relayStateMessage(.flagNotChangeable(module, flag: pulse)) == RelayStateLinkingError.flagNotChangeable(module, flag: pulse).description
      + " Run 'insteon device 1A.2B.3C set pulse off', link it, then run 'insteon device 1A.2B.3C set pulse on'.")
    for undescribed in [
      RelayStateLinkingError.stateHoldingNotDescribed(module, product: "Example"),
      .stateHoldingFlagUnknown(module, flag: "hum"),
      .restStateUnknown(module, action: "closed")
    ] {

      #expect(LinkingEventText.relayStateMessage(undescribed) == undescribed.description + " Link it without a relay state with 'insteon link 1A.2B.3C'.")

    }

    // A guard refused the message, so no setting command is suggested.
    let notWritable = RelayStateLinkingError.flagNotWritable(module, flag: pulse, reason: Failure())

    #expect(LinkingEventText.relayStateMessage(notWritable) == notWritable.description
      + " See its settings with 'insteon device 1A.2B.3C settings'; link it without a relay state with 'insteon link 1A.2B.3C'.")
    #expect(!LinkingEventText.relayStateMessage(notWritable).contains(" set pulse"))
    #expect(LinkingEventText.relayStateMessage(.notARelay(module, product: "Example")) == RelayStateLinkingError.notARelay(module, product: "Example").description)

  }

  @Test func saysWhatAGroupOnAndOffDoToTheRelay() {

    #expect(notes(.relayState(.recorded(link()))) == ["1A.2B.3C recorded its relay on: a group On turns the relay on, and a group Off turns it off."])
    #expect(notes(.relayState(.recorded(link(.off, pulsing: true)))) == [
      "1A.2B.3C recorded its relay off: a group On turns the relay off, and a group Off turns it on. "
        + "Its Pulse flag is on, so the relay holds that state only until it returns to off by itself."
    ])
    #expect(notes(.relayState(.recorded(link(pulsing: true, both: true)))) == [
      "1A.2B.3C linked without switching its relay, whose record holds Data 1 0xFF. "
        + "Its Pulse and Pulse on both flags are on, so every On and Off only pulses it and the state is ignored."
    ])
    // pulseBoth alone isn't the catalog's pulsing set, so the relay holds the state.
    #expect(notes(.relayState(.recorded(link(both: true)))) == ["1A.2B.3C recorded its relay on: a group On turns the relay on, and a group Off turns it off."])
    // The command's failure says what the record holds instead.
    #expect(notes(.relayState(.recorded(link(record: .recordedOtherState(module, group: 2, data1: 0x00, requested: .on))))).isEmpty)

  }

  @Test func failsTheCommandOnceForEverythingThatDidntGoAsAsked() {

    let message = { (error: any Error) -> String in (error as? RelayStateLinkingError)?.description ?? "It failed." }
    let otherState = RelayStateLinkingError.recordedOtherState(module, group: 2, data1: 0x00, requested: .on)
    let notRestored = RelayStateLinkingError.flagNotRestored(module, flag: pulse, reason: Failure())

    func failure(_ link: RelayStateLink?, linkBack: (any Error)? = nil) -> String? {

      LinkingEventText.relayStateFailure(DeviceLinkingResult(links: [], device: nil, linkBackFailure: linkBack, relayState: link), message: message)

    }

    #expect(failure(nil) == nil)
    #expect(failure(link()) == nil)
    #expect(failure(link(record: otherState)) == "1A.2B.3C is linked. " + otherState.description
      + " Run 'insteon link 1A.2B.3C --group 2 --relay-state on' again.")
    #expect(failure(link(pulsing: true, restore: [notRestored])) == "1A.2B.3C is linked. What linking changed wasn't all put back, as said above.")
    #expect(failure(link(), linkBack: Failure()) == "1A.2B.3C is linked. It didn't link back: It failed. "
      + "To link back with its SET button, run 'insteon link 1A.2B.3C --responder'.")

  }

  @Test func printsTheRelayStateAsJSON() throws {

    let notRestored = RelayStateLinkingError.flagNotRestored(module, flag: pulse, reason: Failure())
    let result = DeviceLinkingResult(links: [], device: nil, linkBackFailure: nil, relayState: link(restore: [notRestored]))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let report = LinkingJSON.report(result, message: { (_: any Error) -> String in "It failed." })

    var withFlag: RelayStateLink = link(restore: [notRestored])
    withFlag.clearedFlags = [pulse]

    #expect(String(decoding: try encoder.encode(report), as: UTF8.self) == """
      {"legs":[],"links":[],"relayState":{"groupOff":"off","groupOn":"on","holdsState":true,"ignoresState":false,"recordedData1":"0xFF",\
      "releasingFlags":[],"restoreFailure":"It failed.","state":"on"}}
      """)
    #expect(LinkingJSON.report(DeviceLinkingResult(links: [], device: nil, linkBackFailure: nil, relayState: withFlag)).relayState?.restored == false)
    // Without a relay state, the object is as it always is.
    #expect(String(decoding: try encoder.encode(LinkingJSON.report(DeviceLinkingResult(links: [], device: nil, linkBackFailure: nil))), as: UTF8.self) == #"{"legs":[],"links":[]}"#)

  }

  /// A made-up relay's catalog: its group 1 is a relay whose responder record's Data 1 holds
  /// the state, and the modem controls it in group 0 and responds to it in group 1.
  static let relayCatalog: DeviceCatalog = {

    let commands = CommandSet(
      id: "exampleTextRelay",
      name: "Example relay",
      summary: "A made-up relay.",
      groupTypes: [
        GroupType(
          name: "relay",
          label: "Relay",
          kind: .relay,
          actions: [GroupType.Action(name: "on", label: "On", command: "lightOn", value: 0xFF), GroupType.Action(name: "off", label: "Off", command: "lightOff")],
          linkData: GroupType.LinkData(responder: [LinkDataByte(position: 1, name: "onLevel", summary: "On or off.")]),
          stateHolding: GroupType.StateHolding(releasedBy: ["pulse"], restState: "off", pulsesOnEveryCommandWhen: [["pulse", "pulseBoth"]])
        )
      ]
    )
    let profile = DeviceProfile(
      model: "9701",
      name: "Example Relay",
      aliases: ["Example Pulser"],
      identities: [DeviceIdentity(category: 0x7A, subcategory: 0x70)],
      commandSets: [CommandSetEntry(commandSet: commands.id, category: 0x7A, subcategory: 0x70)],
      groups: [DeviceProfile.Group(number: 1, name: "Relay", role: .both, type: "relay")],
      lifecycle: DeviceLifecycle(fromHub: DeviceLifecycle.HubLinking(legs: [
        DeviceLifecycle.HubLinking.Leg(modemRole: .controller, modemGroup: 0x00, deviceGroup: 0x01),
        DeviceLifecycle.HubLinking.Leg(modemRole: .responder, modemGroup: 0x01, deviceGroup: 0x01)
      ]))
    )

    return DeviceCatalog(profiles: [profile], commandSets: [commands])

  }()

  /// The plan `link --database --relay-state` makes for the made-up relay, whose database
  /// holds a controller record of the modem and a free slot below it.
  func relayPlan(_ state: RelayState) throws -> DatabaseLinkPlan {

    let identity = SetButtonPressed(sender: module, role: .responder, category: 0x7A, subcategory: 0x70, firmwareVersion: 0x41)
    let description: DeviceDescription = Self.relayCatalog.describe(category: 0x7A, subcategory: 0x70, firmwareVersion: 0x41)
    let reading = DeviceLinkingCoordinator.DatabaseReading(
      device: module,
      modem: modem,
      identification: DeviceIdentification(device: module, engine: .i2cs, acceptsModem: true, identity: identity),
      engine: .i2cs,
      description: description,
      deviceRecords: [
        AllLinkRecordResponse(sender: module, address: 0x0FFF, record: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x01, address: modem)),
        AllLinkRecordResponse(sender: module, address: 0x0FF7, record: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0x22), group: 0x09, address: InsteonAddress(0x2C, 0x3D, 0x02))),
        AllLinkRecordResponse(sender: module, address: 0x0FEF, record: AllLinkRecord(flags: [], group: 0x00, address: InsteonAddress(0x00, 0x00, 0x00)))
      ],
      allModemRecords: [],
      modemLinkData: nil
    )
    let legs: [HubLinkingLeg] = try #require(HubLinkingLeg.legs(of: description, device: module))

    return try DeviceLinkingCoordinator.linkPlan(reading: reading, legs: legs, relayState: state)

  }

  @Test func warnsThatARelayWithAReleasingFlagOnDoesntKeepTheStateItsRecordHolds() throws {

    var plan: DatabaseLinkPlan = try relayPlan(.on)
    plan.relayHolding = holding([pulse])

    #expect(DatabaseLinkText.plan(plan).last == "Data 1 of the device's responder record is 0xFF, the relay on, but its Pulse flag is on, "
      + "so the relay doesn't hold a state: it returns to off by itself. The record holds the state only with that flag off, and this plan writes no flag.")

    plan.relayHolding = holding([pulse, pulseBoth])

    #expect(DatabaseLinkText.plan(plan).last == "Data 1 of the device's responder record is 0xFF, the relay on, but its Pulse and Pulse on both flags are on, "
      + "so every On and Off only pulses the relay and the state is ignored. This plan writes no flag.")

    // pulseBoth alone isn't the catalog's pulsing set, so the relay holds the state.
    var holds: DatabaseLinkPlan = try relayPlan(.off)
    holds.relayHolding = holding([pulseBoth])

    #expect(DatabaseLinkText.plan(holds).last == "Data 1 of the device's responder record is 0x00, the relay off: a group On turns the relay off, and a group Off turns it on.")

    let report: DatabaseLinkText.Report = DatabaseLinkText.report(plan, isDryRun: true)

    #expect(report.relayFlagsOn == ["pulse", "pulseBoth"])
    #expect(report.relayHoldsState == false)
    #expect(report.relayIgnoresState == true)

    var plain: DatabaseLinkPlan = try relayPlan(.on)
    plain.relayHolding = holding()

    #expect(DatabaseLinkText.report(plain, isDryRun: true).relayFlagsOn == [])
    #expect(DatabaseLinkText.report(plain, isDryRun: true).relayHoldsState == true)

  }

  @Test func showsTheRelayStateARelaysDryRunWrites() throws {

    let on: [String] = DatabaseLinkText.plan(try relayPlan(.on))
    let off: [String] = DatabaseLinkText.plan(try relayPlan(.off))

    #expect(on == [
      "Linking 1A.2B.3C (Example Relay 9701 (Example Pulser)) by writing ALL-Link records directly, 3 writes:",
      "  1. Write the device's responder record for group 0 at 0x0FF7: 11.22.33, data FF 00 00.",
      "  2. Add the modem's controller record for group 0, naming the device.",
      "  3. Add the modem's responder record for group 1, naming the device.",
      "Already in place:",
      "  The device's controller record for group 1 at 0x0FFF naming 11.22.33, data 00 00 00.",
      "Data 1 of the device's responder record is 0xFF, the relay on: a group On turns the relay on, and a group Off turns it off."
    ])
    #expect(off.first { (line: String) -> Bool in line.hasPrefix("  1.") } == "  1. Write the device's responder record for group 0 at 0x0FF7: 11.22.33, data 00 00 00.")
    #expect(off.last == "Data 1 of the device's responder record is 0x00, the relay off: a group On turns the relay off, and a group Off turns it on.")

  }

  @Test func showsTheData1ADatabaseLinkWrites() {

    var plan = DatabaseLinkPlan(
      device: module,
      modem: modem,
      direction: .link,
      info: nil,
      engine: .i2cs,
      steps: [
        DatabaseLinkStep(
          kind: .addDeviceRecord,
          written: AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x00, address: modem, data1: 0x00, data2: 0x1C, data3: 0x01),
          memoryAddress: 0x0FF7
        )
      ],
      linksInPlace: [],
      orphans: [],
      deviceRecords: [],
      modemRecords: [],
      allModemRecords: []
    )

    plan.relayState = .off

    #expect(DatabaseLinkText.plan(plan).last == "Data 1 of the device's responder record is 0x00, the relay off: a group On turns the relay off, and a group Off turns it on.")

    let report: DatabaseLinkText.Report = DatabaseLinkText.report(plan, isDryRun: true)

    #expect(report.relayState == "off")
    #expect(report.relayData1 == "0x00")

  }

}
