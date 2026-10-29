import Testing
import InsteonProtocol

struct ProtocolNamesTests {

  // MARK: - Commands

  static let commandNames: [(UInt8, String?)] = [
    (0x03, "Product Data Request"),
    (0x0D, "Get Insteon Engine Version"),
    (0x0F, "Ping"),
    (0x10, "ID Request"),
    (0x11, "Light On"),
    (0x12, "Light On Fast"),
    (0x13, "Light Off"),
    (0x14, "Light Off Fast"),
    (0x15, "Light Brighten One Step"),
    (0x16, "Light Dim One Step"),
    (0x17, "Light Start Manual Change"),
    (0x18, "Light Stop Manual Change"),
    (0x19, "Light Status Request"),
    (0x01, nil),
    (0x2E, nil),
    (0xFF, nil)
  ]

  @Test(arguments: commandNames)
  func namesTheCommonDirectCommands(_ command1: UInt8, _ name: String?) {

    #expect(StandardDirectCommand.name(command1: command1) == name)

  }

  @Test func namesEachCommandItsCaseEncodes() {

    #expect(StandardDirectCommand.name(command1: StandardDirectCommand.idRequest.command.command1) == "ID Request")
    #expect(StandardDirectCommand.name(command1: StandardDirectCommand.on(level: 0xFF).command.command1) == "Light On")
    #expect(StandardDirectCommand.name(command1: StandardDirectCommand.statusRequest().command.command1) == "Light Status Request")

  }

  // MARK: - Message types

  static let messageTypeNames: [(MessageFlags.MessageType, String)] = [
    (.direct, "direct"),
    (.directAcknowledgment, "ACK"),
    (.directNegativeAcknowledgment, "NAK"),
    (.broadcast, "broadcast"),
    (.allLinkBroadcast, "ALL-Link broadcast"),
    (.allLinkCleanup, "ALL-Link cleanup"),
    (.allLinkCleanupAcknowledgment, "ALL-Link cleanup ACK"),
    (.allLinkCleanupNegativeAcknowledgment, "ALL-Link cleanup NAK")
  ]

  @Test(arguments: messageTypeNames)
  func namesMessageTypes(_ type: MessageFlags.MessageType, _ name: String) {

    #expect(type.description == name)

  }

  @Test func namesEveryMessageType() {

    let names: Set<String> = Set(MessageFlags.MessageType.allCases.map(\.description))

    #expect(names.count == MessageFlags.MessageType.allCases.count)

  }

  // MARK: - NAK reasons

  static let nakSummaries: [(NAKReason, String)] = [
    (.notLinked, "it isn't linked to the modem"),
    (.noLoad, "it has no load connected"),
    (.invalidCommand, "it doesn't support the command"),
    (.databaseSearchPending, "it's still searching its ALL-Link database"),
    (.illegalValue, "a value is out of range"),
    (.groupZeroCommand, "the command isn't allowed for group 0"),
    (.databaseFull, "its ALL-Link database is full"),
    (.noHardware, "it lacks the hardware for the command"),
    (NAKReason(rawValue: 0x0A), "NAK reason 0x0A"),
    (NAKReason(rawValue: 0xF0), "NAK reason 0xF0")
  ]

  @Test(arguments: nakSummaries)
  func summarizesNAKReasons(_ reason: NAKReason, _ summary: String) {

    #expect(reason.summary == summary)

  }

  // MARK: - Serial commands

  static let serialCommandNames: [(SerialCommandNumber, String)] = [
    (.getModemInfo, "Get IM Info"),
    (.sendMessage, "Send Insteon Standard or Extended Message"),
    (.startAllLinking, "Start ALL-Linking"),
    (.cancelAllLinking, "Cancel ALL-Linking"),
    (.getFirstAllLinkRecord, "Get First ALL-Link Record"),
    (.getNextAllLinkRecord, "Get Next ALL-Link Record"),
    (.manageAllLinkRecord, "Manage ALL-Link Record"),
    (.manageDeviceRecord, "Database Commands")
  ]

  @Test(arguments: serialCommandNames)
  func namesSerialCommands(_ number: SerialCommandNumber, _ name: String) {

    #expect(number.name == name)

  }

  @Test func namesEverySerialCommandDifferently() {

    let names: Set<String> = Set(SerialCommandNumber.allCases.map(\.name))

    #expect(names.count == SerialCommandNumber.allCases.count)

  }

  // MARK: - Engines, modes and roles

  @Test func namesEnginesAsTheDocumentsDo() {

    #expect(InsteonEngine.i1.description == "i1")
    #expect(InsteonEngine.i2.description == "i2")
    #expect(InsteonEngine.i2cs.description == "i2CS")
    #expect("\(InsteonEngine.i2cs)" == "i2CS")

  }

  @Test func namesTheModemsRoleInALink() {

    #expect(AllLinkMode.responder.description == "responder")
    #expect(AllLinkMode.controller.description == "controller")
    #expect(AllLinkMode.controllerOrResponder.description == "controller or responder")
    #expect(AllLinkMode.delete.description == "deleted")

  }

  @Test func namesTheRoleASETButtonPressedBroadcastOffers() {

    #expect(SetButtonPressed.Role.responder.description == "responder")
    #expect(SetButtonPressed.Role.controller.description == "controller")

  }

}
