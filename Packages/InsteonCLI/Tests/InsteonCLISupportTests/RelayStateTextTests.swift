import Foundation
import Testing
@testable import InsteonCLISupport
@testable import InsteonCore
import InsteonProtocol

/// Parsing `link --relay-state`, and what `insteon link` prints while it puts a relay in the
/// state and after it links.
struct RelayStateTextTests {

  let module = InsteonAddress(0x1A, 0x2B, 0x3C)

  let modem = InsteonAddress(0x11, 0x22, 0x33)

  struct Failure: Error {}

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

  func plan(before: RelayState = .off, momentary: Bool = false, pulses: Bool = false, state: RelayState = .on) -> RelayLinkPlan {

    RelayLinkPlan(device: module, state: state, before: before, isMomentary: momentary, pulsesOnBothCommands: pulses)

  }

  @Test func showsWhatTheLinkWillSwitchAndPutBack() {

    #expect(RelayLinkText.plan(plan(momentary: true)) == [
      "Linking 1A.2B.3C so a group On turns its relay on and a group Off turns it off:",
      "  1. Turn its momentary flag off for the link, so the relay holds its state.",
      "  2. Turn the relay on. Whatever it controls, such as a garage door opener, a lock or a valve, acts on it.",
      "  3. Link it, then turn the relay off again, since a momentary relay rests open, and turn its momentary flag back on."
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
    #expect(RelayLinkText.plan(plan(momentary: true, pulses: true)) == [
      "1A.2B.3C's relay is momentary with its momentaryOnBothCommands flag on, so every On and Off only pulses it and the state is ignored.",
      "  1. Link it. The relay isn't switched and no flag is written."
    ])
    #expect(RelayLinkText.plan(plan(before: .on, pulses: true)) == [
      "1A.2B.3C's momentaryOnBothCommands flag is on though its relay isn't momentary, a mode whose effect isn't verified, so the relay isn't switched.",
      "  1. Link it. No flag is written; its record holds on, the state the relay is in, so a group On turns the relay on and a group Off turns it off."
    ])

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

    let differs = RelayStateLinkingError.unverifiedModeStateDiffers(module, flag: "momentaryOnBothCommands", reads: .off, requested: .on)

    #expect(LinkingEventText.relayStateMessage(differs, group: 2) == differs.description
      + " Run 'insteon device 1A.2B.3C set momentaryOnBothCommands off' and link again, or run 'insteon link 1A.2B.3C --group 2 --relay-state off'.")

  }

  @Test func doesntClaimAStateTheRelayIgnores() throws {

    let ignored = RelayStateLink(device: module, state: .on, group: 2, recordedData1: 0x00, isMomentary: true, pulsesOnBothCommands: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let report = LinkingJSON.report(DeviceLinkingResult(links: [], device: nil, linkBackFailure: nil, relayState: ignored), message: { (_: any Error) -> String in "" })

    #expect(String(decoding: try encoder.encode(report.relayState), as: UTF8.self) == """
      {"ignoresState":true,"isMomentary":true,"leavesUnverifiedMode":false,"pulsesOnBothCommands":true,"recordedData1":"0x00","state":"on"}
      """)
    #expect(!notes(.relayState(.recorded(ignored))).joined().contains("group On turns"))

    let unverified = RelayStateLink(device: module, state: .off, group: 2, recordedData1: 0x00, isMomentary: false, pulsesOnBothCommands: true)

    #expect(LinkingJSON.report(DeviceLinkingResult(links: [], device: nil, linkBackFailure: nil, relayState: unverified)).relayState?.leavesUnverifiedMode == true)
    #expect(LinkingJSON.report(DeviceLinkingResult(links: [], device: nil, linkBackFailure: nil, relayState: unverified)).relayState?.groupOn == "off")

  }

  @Test func printsThePlanAsJSONForADryRun() throws {

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    #expect(String(decoding: try encoder.encode(RelayLinkText.report(plan(momentary: true), isDryRun: true)), as: UTF8.self) == """
      {"before":"off","clearedFlag":"momentary","device":"1A.2B.3C","dryRun":true,"ignoresState":false,"isMomentary":true,\
      "leavesUnverifiedMode":false,"opensAfterLinking":true,"pulsesOnBothCommands":false,"state":"on","switchesBackOnFailure":false,"switchesRelay":true}
      """)

  }

  @Test func asksOnlyWhenTheRelayIsSwitched() {

    #expect(RelayLinkText.question(plan()) == "Switch 1A.2B.3C's relay on and link it? [y/N]")
    #expect(RelayLinkText.question(plan(before: .on)) == nil)
    #expect(RelayLinkText.question(plan(momentary: true, pulses: true)) == nil)
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

  func link(_ state: RelayState = .on, isMomentary: Bool = false, pulses: Bool = false, record: RelayStateLinkingError? = nil, restore: [RelayStateLinkingError] = []) -> RelayStateLink {

    RelayStateLink(
      device: module,
      state: state,
      group: 2,
      recordedData1: state.data1,
      recordFailure: record,
      clearedFlag: isMomentary ? "momentary" : nil,
      isMomentary: isMomentary,
      pulsesOnBothCommands: pulses,
      restoreFailures: restore
    )

  }

  @Test func saysEachStepOfPuttingTheRelayInItsState() {

    #expect(notes(.relayState(.clearingFlag(module, flag: "momentary"))) == [
      "Turning 1A.2B.3C's momentary flag off for the link, so its relay holds its state..."
    ])
    #expect(notes(.relayState(.settingRelay(module, .on))) == ["Turning 1A.2B.3C's relay on, so it links with the relay on..."])
    #expect(notes(.relayState(.settingRelay(module, .off))) == ["Turning 1A.2B.3C's relay off, so it links with the relay off..."])
    #expect(notes(.relayState(.relayAlreadySet(module, .off))) == ["1A.2B.3C's relay is already off, so it links with the relay off."])
    #expect(notes(.relayState(.stateIgnored(module, flag: "momentaryOnBothCommands", isMomentary: true))) == [
      "1A.2B.3C's relay is momentary with its momentaryOnBothCommands flag on, so every On and Off only pulses it and the state is ignored. "
        + "It's linked without switching the relay or writing a flag."
    ])
    #expect(notes(.relayState(.stateIgnored(module, flag: "momentaryOnBothCommands", isMomentary: false))) == [
      "1A.2B.3C's momentaryOnBothCommands flag is on though its relay isn't momentary, a mode whose effect isn't verified, "
        + "so it's linked without switching the relay or writing a flag, and records the state the relay is in."
    ])
    #expect(notes(.relayState(.relayLeft(module, reads: .off))) == ["1A.2B.3C's relay reads off, so it's left as it is rather than switched again."])
    #expect(notes(.relayState(.relayConfirmed(module, .on))).isEmpty)
    #expect(notes(.relayState(.returningRelay(module, .off))) == ["Turning 1A.2B.3C's relay off after the link..."])
    #expect(notes(.relayState(.restoringFlag(module, flag: "momentary"))) == ["Turning 1A.2B.3C's momentary flag back on..."])
    #expect(notes(.relayState(.flagRestored(module, flag: "momentary"))).isEmpty)

  }

  @Test func saysWhatDidntGoBackWithTheCommandThatFixesIt() {

    let notRestored = RelayStateLinkingError.flagNotRestored(module, flag: "momentary", reason: Failure())
    let unconfirmed = RelayStateLinkingError.flagRestoreUnconfirmed(module, flag: "momentary", reason: Failure())
    let notReturned = RelayStateLinkingError.relayNotReturned(module, state: .off, reason: Failure())

    #expect(notes(.relayState(.restoreFailed(module, notRestored))) == [
      notRestored.description + " Turn it back on with 'insteon device 1A.2B.3C set momentary on'."
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
    #expect(LinkingEventText.relayStateMessage(.momentaryNotChangeable(module, flag: "momentary")) == RelayStateLinkingError.momentaryNotChangeable(module, flag: "momentary").description
      + " Run 'insteon device 1A.2B.3C set momentary off', link it, then run 'insteon device 1A.2B.3C set momentary on'.")
    #expect(LinkingEventText.relayStateMessage(.notARelay(module, product: "Example")) == RelayStateLinkingError.notARelay(module, product: "Example").description)

  }

  @Test func saysWhatAGroupOnAndOffDoToTheRelay() {

    #expect(notes(.relayState(.recorded(link()))) == ["1A.2B.3C recorded its relay on: a group On turns the relay on, and a group Off turns it off."])
    #expect(notes(.relayState(.recorded(link(.off, isMomentary: true)))) == [
      "1A.2B.3C recorded its relay off: a group On turns the relay off, and a group Off turns it on. "
        + "The relay is momentary, so it holds that state only for its momentary time."
    ])
    #expect(notes(.relayState(.recorded(link(isMomentary: true, pulses: true)))) == [
      "1A.2B.3C linked without switching its relay, whose record holds Data 1 0xFF. "
        + "Its relay is momentary with momentaryOnBothCommands on, so every On and Off only pulses it and the state is ignored."
    ])
    #expect(notes(.relayState(.recorded(link(isMomentary: false, pulses: true)))) == [
      "1A.2B.3C linked without switching its relay, whose record holds Data 1 0xFF. "
        + "Its momentaryOnBothCommands flag is on though the relay isn't momentary, a mode whose effect isn't verified."
    ])
    // The command's failure says what the record holds instead.
    #expect(notes(.relayState(.recorded(link(record: .recordedOtherState(module, group: 2, data1: 0x00, requested: .on))))).isEmpty)

  }

  @Test func failsTheCommandOnceForEverythingThatDidntGoAsAsked() {

    let message = { (error: any Error) -> String in (error as? RelayStateLinkingError)?.description ?? "It failed." }
    let otherState = RelayStateLinkingError.recordedOtherState(module, group: 2, data1: 0x00, requested: .on)
    let notRestored = RelayStateLinkingError.flagNotRestored(module, flag: "momentary", reason: Failure())

    func failure(_ link: RelayStateLink?, linkBack: (any Error)? = nil) -> String? {

      LinkingEventText.relayStateFailure(DeviceLinkingResult(links: [], device: nil, linkBackFailure: linkBack, relayState: link), message: message)

    }

    #expect(failure(nil) == nil)
    #expect(failure(link()) == nil)
    #expect(failure(link(record: otherState)) == "1A.2B.3C is linked. " + otherState.description
      + " Run 'insteon link 1A.2B.3C --group 2 --relay-state on' again.")
    #expect(failure(link(isMomentary: true, restore: [notRestored])) == "1A.2B.3C is linked. What linking changed wasn't all put back, as said above.")
    #expect(failure(link(), linkBack: Failure()) == "1A.2B.3C is linked. It didn't link back: It failed. "
      + "To link back with its SET button, run 'insteon link 1A.2B.3C --responder'.")

  }

  @Test func printsTheRelayStateAsJSON() throws {

    let notRestored = RelayStateLinkingError.flagNotRestored(module, flag: "momentary", reason: Failure())
    let result = DeviceLinkingResult(links: [], device: nil, linkBackFailure: nil, relayState: link(isMomentary: false, restore: [notRestored]))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let report = LinkingJSON.report(result, message: { (_: any Error) -> String in "It failed." })

    var withFlag: RelayStateLink = link(isMomentary: false, restore: [notRestored])
    withFlag.clearedFlag = "momentary"

    #expect(String(decoding: try encoder.encode(report), as: UTF8.self) == """
      {"legs":[],"links":[],"relayState":{"groupOff":"off","groupOn":"on","ignoresState":false,"isMomentary":false,"leavesUnverifiedMode":false,\
      "pulsesOnBothCommands":false,"recordedData1":"0xFF","restoreFailure":"It failed.","state":"on"}}
      """)
    #expect(LinkingJSON.report(DeviceLinkingResult(links: [], device: nil, linkBackFailure: nil, relayState: withFlag)).relayState?.restored == false)
    // Without a relay state, the object is as it always is.
    #expect(String(decoding: try encoder.encode(LinkingJSON.report(DeviceLinkingResult(links: [], device: nil, linkBackFailure: nil))), as: UTF8.self) == #"{"legs":[],"links":[]}"#)

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
