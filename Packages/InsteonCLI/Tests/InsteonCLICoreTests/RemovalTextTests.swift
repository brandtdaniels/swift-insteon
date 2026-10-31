import Foundation
import Testing
import InsteonCLICore
import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// What `insteon remove` asks and prints, and its JSON, which scripts read key by key.
struct RemovalTextTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let keypad = InsteonAddress(0x4E, 0x5F, 0x01)

  let sensor = InsteonAddress(0x4E, 0x5F, 0x02)

  struct Failure: Error {}

  /// A made-up catalog with the lamp's product, and reset steps for it.
  let catalog = DeviceCatalog(profiles: [
    DeviceProfile(
      model: "9401",
      name: "Example Removed Dimmer",
      identities: [DeviceIdentity(category: 0x01, subcategory: 0x7A)],
      groups: [DeviceProfile.Group(number: 1, name: "Load", role: .responder)],
      lifecycle: DeviceLifecycle(
        reset: DeviceLifecycle.Procedure(
          steps: [
            DeviceLifecycle.Step(text: "Pull the air gap out for 10 seconds."),
            DeviceLifecycle.Step(text: "Push it in and hold the paddle down.", expectation: "A long beep")
          ],
          notes: ["The LED blinks while it resets."]
        ),
        resetErases: [.settings, .links]
      )
    )
  ])

  /// The lamp as the registry knows it.
  var registered: RegisteredDevice {

    RegisteredDevice(
      address: lamp,
      identity: ReportedIdentity(category: 0x01, subcategory: 0x7A, firmwareVersion: 0x41),
      deviceDescription: catalog.describe(category: 0x01, subcategory: 0x7A, firmwareVersion: 0x41)
    )

  }

  var label: String {

    LinkingInstructions.deviceLabel(lamp, profile: registered.deviceDescription.profile)

  }

  var reset: FactoryResetSteps {

    FactoryResetSteps(
      address: lamp,
      deviceDescription: registered.deviceDescription,
      procedure: registered.deviceDescription.profile?.lifecycle?.reset,
      erases: [.links, .settings]
    )

  }

  func message(_ error: any Error) -> String {

    "It didn't answer."

  }

  /// Encodes a value with its keys sorted, on one line.
  func encoded(_ value: some Encodable) throws -> String {

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    return String(decoding: try encoder.encode(value), as: UTF8.self)

  }

  // MARK: - Asking

  @Test func asksBeforeRemovingAndSaysWhatForcingDoes() {

    #expect(RemovalText.question(device: "1A.2B.3C", forcesModemSide: false)
      == "Remove 1A.2B.3C from the network? Its links with the modem are removed and the identity cache forgets it. [y/N]")
    #expect(RemovalText.question(device: "1A.2B.3C", forcesModemSide: true).contains("which is only right for a device that's gone"))
    #expect(RemovalText.declined(device: "1A.2B.3C") == "1A.2B.3C wasn't removed.")

  }

  @Test func offersForcingWhenTheLinksCantBeRemoved() {

    let text: String = RemovalText.notRemoved(lamp, device: "1A.2B.3C", reason: "It didn't answer.")

    #expect(text.hasPrefix("1A.2B.3C wasn't removed: its links with the modem couldn't be removed without its SET button. It didn't answer."))
    #expect(text.contains("'insteon remove 1A.2B.3C --force-modem-side'"))

  }

  // MARK: - Results

  @Test func saysTheDeviceWasForgotten() {

    #expect(RemovalText.forgotten(ForgottenDevice(address: lamp, device: nil)) == [
      "Removed 1A.2B.3C from the network, and the identity cache forgot it."
    ])
    #expect(RemovalText.forgotten(ForgottenDevice(address: lamp, device: registered)) == [
      "Removed \(label) from the network, and the identity cache forgot it."
    ])

  }

  @Test func listsTheRecordsOtherDevicesHoldAndThoseNotRead() {

    let scene = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 3, address: lamp)
    let response = AllLinkRecordResponse(sender: keypad, address: 0x0FF7, record: scene)
    let scan = LeftoverRecordScan(
      removedDevice: lamp,
      holders: [LeftoverRecords(address: keypad, device: nil, records: [response])],
      unread: [UnreadDatabase(address: sensor, device: nil, reason: Failure())]
    )

    #expect(RemovalText.leftoverRecords(scan, message: message) == [
      "4E.5F.01 still holds 1 record for 1A.2B.3C: controller in group 3 at 0x0FF7.",
      "Those records weren't changed. Removing 1A.2B.3C from those devices' scenes clears them.",
      "Couldn't read the ALL-Link database of 4E.5F.02, so it may hold records for 1A.2B.3C too: It didn't answer."
    ])
    #expect(RemovalText.leftoverRecords(LeftoverRecordScan(removedDevice: lamp, holders: [], unread: []), message: message) == [
      "No other device the identity cache knows holds records for 1A.2B.3C."
    ])

  }

  @Test func showsTheCatalogsResetStepsAndSaysTheCommandDoesntReset() {

    #expect(RemovalText.factoryReset(reset) == [
      "To restore the factory settings of \(label), which the command doesn't do:",
      "  1. Pull the air gap out for 10 seconds.",
      "  2. Push it in and hold the paddle down. [A long beep]",
      "A factory reset erases its ALL-Link database and its settings.",
      "Note: The LED blinks while it resets."
    ])

    let unknown = FactoryResetSteps(address: lamp, deviceDescription: nil, procedure: nil, erases: [])

    #expect(RemovalText.factoryReset(unknown) == [
      "The Insteon device catalog has no factory reset steps for 1A.2B.3C; its owner's manual has them. "
        + "A reset erases the links the device keeps itself. The command doesn't reset it."
    ])

  }

  // MARK: - Events

  @Test func saysWhatTheRemovalDoesAsItGoes() {

    let notes = { (event: LinkingEvent) -> [String] in

      LinkingEventText.notes(for: event, message: { (_: any Error) -> String in "It failed." })

    }

    #expect(notes(.deletingModemRecords(lamp)) == [
      "1A.2B.3C didn't answer, so the modem's records for it are being deleted with Manage ALL-Link Record, "
        + "as --force-modem-side asks. The device keeps its own records."
    ])
    #expect(notes(.scanningDatabase(keypad, removedDevice: lamp)) == ["Reading 4E.5F.01's ALL-Link database for records that name 1A.2B.3C..."])
    // The results are the command's to print.
    #expect(notes(.forgotten(ForgottenDevice(address: lamp, device: nil))).isEmpty)
    #expect(notes(.leftoverRecords(LeftoverRecordScan(removedDevice: lamp, holders: [], unread: []))).isEmpty)
    #expect(notes(.factoryReset(reset)).isEmpty)

  }

  // MARK: - JSON

  @Test func printsTheRemovalAsJSON() throws {

    let scene = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 1, address: lamp)
    let result = DeviceRemovalResult(
      removed: RemovedLinks(address: lamp, device: registered, links: [ModemLink(modemRole: .responder, group: 1), ModemLink(modemRole: .controller, group: 0)]),
      remainingLinks: [],
      remoteUnlinkingFailure: nil,
      deletedModemRecords: [],
      forgotten: ForgottenDevice(address: lamp, device: registered),
      leftoverRecords: LeftoverRecordScan(
        removedDevice: lamp,
        holders: [LeftoverRecords(address: keypad, device: nil, records: [AllLinkRecordResponse(sender: keypad, address: 0x0FFF, record: scene)])],
        unread: [UnreadDatabase(address: sensor, device: nil, reason: Failure())]
      ),
      factoryReset: reset
    )
    let product: String = registered.deviceDescription.displayName ?? ""

    #expect(try encoded(LinkingJSON.removal(result, message: message)) == """
      {"address":"1A.2B.3C","deletedModemRecords":[],\
      "factoryReset":{"erases":["links","settings"],"notes":["The LED blinks while it resets."],\
      "steps":["Pull the air gap out for 10 seconds.","Push it in and hold the paddle down. [A long beep]"]},\
      "leftoverRecords":[{"address":"4E.5F.01","records":[{"group":1,"recordAddress":"0x0FFF","role":"responder"}]}],\
      "product":"\(product)",\
      "remainingLinks":[],\
      "removedLinks":[{"group":1,"modemRole":"responder"},{"group":0,"modemRole":"controller"}],\
      "unreadDevices":[{"address":"4E.5F.02","error":"It didn't answer."}]}
      """)

  }

  @Test func printsTheModemsDeletedRecordsAndLeavesOutWhatWasntDone() throws {

    let record = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0, address: lamp)
    let result = DeviceRemovalResult(
      removed: RemovedLinks(address: lamp, device: nil, links: []),
      remainingLinks: nil,
      remoteUnlinkingFailure: Failure(),
      deletedModemRecords: [record],
      forgotten: ForgottenDevice(address: lamp, device: nil),
      leftoverRecords: nil,
      factoryReset: FactoryResetSteps(address: lamp, deviceDescription: nil, procedure: nil, erases: [])
    )

    #expect(try encoded(LinkingJSON.removal(result, message: message)) == """
      {"address":"1A.2B.3C","deletedModemRecords":[{"group":0,"modemRole":"controller"}],\
      "factoryReset":{"erases":[],"notes":[]},\
      "remoteUnlinkingFailure":"It didn't answer.","removedLinks":[]}
      """)

  }

}
