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

    #expect(on == .link(LinkOptions(device: module, group: 2, relayState: .on)))
    #expect(off == .link(LinkOptions(device: module, relayState: .off)))
    #expect(database == .link(LinkOptions(device: module, database: DatabaseWriteOptions(isDryRun: true), relayState: .on)))

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

  }

  // MARK: - What's printed

  @Test func saysEachStepOfPuttingTheRelayInItsState() {

    #expect(notes(.relayState(.clearingFlag(module, flag: "momentary"))) == [
      "Turning 1A.2B.3C's momentary flag off for the link, so its relay holds its state..."
    ])
    #expect(notes(.relayState(.settingRelay(module, .on))) == ["Turning 1A.2B.3C's relay on with Light On, so it links with the relay on..."])
    #expect(notes(.relayState(.settingRelay(module, .off))) == ["Turning 1A.2B.3C's relay off with Light Off, so it links with the relay off..."])
    #expect(notes(.relayState(.relayAlreadySet(module, .off))) == ["1A.2B.3C's relay is already off, so it links with the relay off."])
    #expect(notes(.relayState(.relayConfirmed(module, .on))).isEmpty)
    #expect(notes(.relayState(.restoringFlag(module, flag: "momentary"))) == ["Turning 1A.2B.3C's momentary flag back on..."])
    #expect(notes(.relayState(.flagRestored(module, flag: "momentary"))).isEmpty)
    #expect(notes(.relayState(.flagNotRestored(module, flag: "momentary", reason: Failure()))) == [
      "1A.2B.3C's momentary flag wasn't turned back on: It failed. "
        + "Turn it on with 'insteon device 1A.2B.3C set momentary on'."
    ])

  }

  @Test func saysWhatAGroupOnAndOffDoToTheRelay() {

    let on = RelayStateLink(device: module, state: .on, isMomentary: false, pulsesOnBothCommands: false)
    let off = RelayStateLink(device: module, state: .off, isMomentary: true, pulsesOnBothCommands: false)
    let pulsing = RelayStateLink(device: module, state: .on, isMomentary: true, pulsesOnBothCommands: true)

    #expect(notes(.relayState(.recorded(on))) == ["1A.2B.3C recorded its relay on: a group On turns the relay on, and a group Off turns it off."])
    #expect(notes(.relayState(.recorded(off))) == [
      "1A.2B.3C recorded its relay off: a group On turns the relay off, and a group Off turns it on. "
        + "The relay is momentary, so it holds that state only for its momentary time."
    ])
    #expect(notes(.relayState(.recorded(pulsing))) == [
      "1A.2B.3C recorded its relay on: a group On turns the relay on, and a group Off turns it off. "
        + "Both On and Off pulse the momentary relay, so the state isn't used while it's momentary."
    ])

  }

  @Test func failsTheCommandWhenTheFlagWasntTurnedBackOn() {

    let message = { (_: any Error) -> String in "It failed." }
    let restored = RelayStateLink(device: module, state: .on, isMomentary: true, pulsesOnBothCommands: false)
    var notRestored = restored

    notRestored.restoreFailure = Failure()

    #expect(LinkingEventText.flagNotRestored(DeviceLinkingResult(links: [], device: nil, linkBackFailure: nil), message: message) == nil)
    #expect(LinkingEventText.flagNotRestored(DeviceLinkingResult(links: [], device: nil, linkBackFailure: nil, relayState: restored), message: message) == nil)
    #expect(LinkingEventText.flagNotRestored(DeviceLinkingResult(links: [], device: nil, linkBackFailure: nil, relayState: notRestored), message: message) == "1A.2B.3C is linked. It failed.")

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

  }

}
