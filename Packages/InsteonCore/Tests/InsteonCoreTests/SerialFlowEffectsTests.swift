import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

/// The effect each serial command a core flow builds declares, so a modem with no command set
/// sends them, and the flows that build them.
struct SerialFlowEffectsTests {

  static let group: AllLinkGroupNumber = AllLinkGroupNumber(rawValue: 0x01)

  static let device: InsteonAddress = InsteonAddress(0x1A, 0x2B, 0x3C)

  static let record: AllLinkRecord = AllLinkRecord(flags: [.inUse, .controller], group: group, address: device)

  /// Every serial command a core flow builds, with the flow and the effect it declares.
  static let flows: [(flow: String, command: SerialCommand, effect: CommandEffect)] = [
    ("every flow that asks the modem who it is", .getModemInfo, .readOnly),
    ("link, with the modem as a responder", .startAllLinking(mode: .responder, group: group), .link),
    ("link, with the modem as a controller", .startAllLinking(mode: .controller, group: group), .link),
    ("link, with the modem as either", .startAllLinking(mode: .controllerOrResponder, group: group), .link),
    ("unlink, deleting a link through the next device's SET button", .startAllLinking(mode: .delete, group: group), .destructive),
    ("link and unlink, taking the modem out of linking mode", .cancelAllLinking, .link),
    ("reading the modem's ALL-Link database", .getFirstAllLinkRecord, .readOnly),
    ("reading the modem's ALL-Link database", .getNextAllLinkRecord, .readOnly),
    ("reading the modem's records for a device", .manageAllLinkRecord(action: .findFirst, record: record), .readOnly),
    ("reading the modem's records for a device", .manageAllLinkRecord(action: .findNext, record: record), .readOnly),
    ("link --database, adding a controller record", .addAllLinkRecord(record), .destructive),
    ("link --database, adding a responder record", .addAllLinkRecord(AllLinkRecord(flags: [.inUse], group: group, address: device)), .destructive),
    ("remove --force-modem-side and unlink --database, deleting a record", .deleteFirstAllLinkRecord(group: group, address: device), .destructive),
    ("scene, sending a command to a group", .sendAllLinkCommand(group: group, command: Command(command1: 0x11, command2: 0xFF)), .actuation),
    ("every message to a device", .sendStandardMessage(StandardMessage(to: device, command: Command(command1: 0x19, command2: 0x00))), .actuation),
    ("every extended message to a device", .sendExtendedMessage(ExtendedMessage(to: device, command: Command(command1: 0x2E, command2: 0x00), userData: UserData())), .actuation),
    ("beep", .beep, .actuation),
    ("beep --double", .doubleBeep, .actuation),
  ]

  @Test func declaresTheEffectOfEverySerialCommandACoreFlowBuilds() {

    for (flow, command, effect) in Self.flows {

      #expect(SerialFlowEffects.declaredEffect(of: command.bytes) == effect, "\(flow): \(command.bytes)")

    }

  }

  @Test func declaresNothingForACommandNoCoreFlowBuilds() {

    let others: [SerialCommand] = [
      .resetModem, .rfSleep, .setAcknowledgmentByte(0x00), .setModemConfiguration(ModemConfiguration(rawValue: 0)), .getModemConfiguration, .cancelCleanup,
      .readDatabase(address: 0x0FFF), .setApplicationRetries(1), .readRadioStatus, .getAllLinkRecordForSender,
      .manageAllLinkRecord(action: .modifyFirstOrAdd, record: Self.record),
    ]

    for command in others {

      #expect(SerialFlowEffects.declaredEffect(of: command.bytes) == nil, "\(command.bytes)")

    }

  }

  /// What `modem send` lets through for each flow's frame when the modem has no command set:
  /// everything its effect lets an unforced send, and what destroys needs `--force`.
  @Test func sendsEveryReadOnlyLinkAndActuationFlowFrameWithoutForceOnAModemWithoutACommandSet() {

    for (flow, command, effect) in Self.flows {

      let decision: SendDecision = SerialCommandPolicy.decision(of: command.bytes, commands: nil, forcing: false)

      #expect(decision == (effect == .destructive ? .needsConsent(.destructive) : .transmit), "\(flow): \(command.bytes)")
      #expect(SerialCommandPolicy.decision(of: command.bytes, commands: nil, forcing: true) == .transmit, "\(flow)")

    }

  }

}
