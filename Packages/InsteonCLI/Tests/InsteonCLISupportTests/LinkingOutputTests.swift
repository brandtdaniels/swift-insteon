import Testing
import InsteonCLISupport
import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// What `insteon link`, `unlink` and `remove` do with each event a coordinator reports: what
/// they save, print or write as JSON.
@Suite(.timeLimit(.minutes(1)))
struct LinkingOutputTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  struct Failure: Error {}

  let message: (any Error) -> String = { (_: any Error) -> String in "It failed." }

  /// A made-up catalog with the lamp's product, on an identity no real product has.
  let catalog = DeviceCatalog(profiles: [
    DeviceProfile(
      model: "EX-LINKED-LAMP",
      name: "Example Linked Lamp",
      identities: [DeviceIdentity(category: 0x01, subcategory: 0x7B)],
      groups: [DeviceProfile.Group(number: 1, name: "Load", role: .responder)]
    )
  ])

  /// The lamp as a registry with the catalog describes it, reporting a firmware version or not.
  func lampDevice(firmwareVersion: FirmwareVersion? = 0x45) async -> RegisteredDevice {

    await DeviceRegistry(catalog: catalog).record(ReportedIdentity(category: 0x01, subcategory: 0x7B, firmwareVersion: firmwareVersion), for: lamp)

  }

  func outputs(_ event: LinkingEvent, printsJSON: Bool = false, namesProducts: Bool = true) -> [LinkingOutput] {

    LinkingOutput.outputs(for: event, printsJSON: printsJSON, namesProducts: namesProducts, message: message)

  }

  // MARK: - A link made

  @Test func savesTheIdentityAndPrintsItWithTheFirstLink() async {

    let registered: RegisteredDevice = await lampDevice()

    let made = LinkMade(address: lamp, group: 1, mode: .controller)
    let info: DeviceInfo = registered.info

    #expect(outputs(.linked(LinkedDevice(link: made, device: registered, leg: .first))) == [
      .saveIdentities,
      .line("Linked 1A.2B.3C in group 1, modem as \(Names.mode(made.mode))."),
      .table([
        ["Category:", Names.category(info.category)],
        ["Subcategory:", "\(info.subcategory)"],
        ["Firmware:", "0x45"],
        ["Product:", info.displayName ?? ""]
      ])
    ])

  }

  @Test func leavesOutTheProductWithoutACatalogAndSaysWhatsNotReported() async {

    let made = LinkMade(address: lamp, group: 1, mode: .controller)
    let unreported: RegisteredDevice = await lampDevice(firmwareVersion: nil)
    let found = outputs(.linked(LinkedDevice(link: made, device: unreported, leg: .first)), namesProducts: false)

    guard case let .table(rows)? = found.last else {

      Issue.record("Expected a table, got \(found).")

      return

    }

    #expect(rows.map { (row: [String]) -> String? in row.first } == ["Category:", "Subcategory:", "Firmware:"])
    #expect(rows.last?.last == "not reported")

  }

  @Test func printsTheLinkBackAloneAndSavesNothingThen() async {

    let registered: RegisteredDevice = await lampDevice()

    let back = LinkMade(address: lamp, group: 1, mode: .responder)

    #expect(outputs(.linked(LinkedDevice(link: back, device: registered, leg: .linkBack))) == [
      .line("Linked 1A.2B.3C in group 1, modem as \(Names.mode(back.mode)).")
    ])

  }

  @Test func onlySavesTheIdentityWithJSON() async {

    let registered: RegisteredDevice = await lampDevice()

    let made = LinkMade(address: lamp, group: 1, mode: .controller)

    #expect(outputs(.linked(LinkedDevice(link: made, device: registered, leg: .first)), printsJSON: true) == [.saveIdentities])

  }

  // MARK: - Links removed

  @Test func printsALinkRemoved() {

    let link = LinkMade(address: lamp, group: 1, mode: .responder)
    let label: String = LinkingInstructions.deviceLabel(lamp, info: nil)

    #expect(outputs(.unlinked(UnlinkedLink(link: link, device: nil))) == [.line("Unlinked \(label) from group 1.")])
    #expect(outputs(.unlinked(UnlinkedLink(link: link, device: nil)), printsJSON: true).isEmpty)

  }

  @Test func printsEachLinkRemovedWithoutTheSETButtonOrThatThereWereNone() async {

    let registered: RegisteredDevice = await lampDevice()

    let label: String = LinkingInstructions.deviceLabel(lamp, info: registered.info)
    let removed = RemovedLinks(address: lamp, device: registered, links: [ModemLink(modemRole: .responder, group: 1), ModemLink(modemRole: .controller, group: 0)])
    let lines: [LinkingOutput] = LinkingJSON.removedLinks(removed).map { (link: LinkingJSON.RemovedLink) -> LinkingOutput in

      .line("Unlinked \(label) from group \(link.group), modem as \(link.modemRole).")

    }

    #expect(outputs(.unlinkedAll(removed)) == lines)
    #expect(lines.count == 2)
    #expect(outputs(.unlinkedAll(RemovedLinks(address: lamp, device: registered, links: []))) == [.line("The modem has no links with \(label).")])

  }

  @Test func printsADeviceForgottenOnlyWithoutJSON() async {

    let registered: RegisteredDevice = await lampDevice()

    let forgotten = ForgottenDevice(address: lamp, device: registered)

    #expect(outputs(.forgotten(forgotten)) == RemovalText.forgotten(forgotten).map(LinkingOutput.line))
    #expect(outputs(.forgotten(forgotten), printsJSON: true).isEmpty)

  }

  @Test func printsWhatRemovingADeviceLeftOnlyWithoutJSON() async {

    let registered: RegisteredDevice = await lampDevice()
    let other = InsteonAddress(0x4E, 0x5F, 0x01)
    let record = LinkRecord(isController: false, isInUse: true, group: 1, address: lamp, data: [0x00, 0x00, 0x00], memoryAddress: 0x0FFF)
    let scan = LeftoverRecordScan(removedDevice: lamp, holders: [LeftoverRecords(address: other, device: nil, records: [record])], unread: [])
    let reset = FactoryResetSteps(
      address: lamp,
      info: registered.info,
      procedure: Instructions(steps: [InstructionStep(text: "Hold the example button for 10 seconds.")], notes: []),
      erases: [.links]
    )
    let events: [(LinkingEvent, [String])] = [
      (.leftoverRecords(scan), RemovalText.leftoverRecords(scan, message: message)),
      (.modemRecordsDeleted(lamp, [record]), RemovalText.modemRecordsDeleted(lamp, [record])),
      (.factoryReset(reset), RemovalText.factoryReset(reset))
    ]

    for (event, lines) in events {

      #expect(!lines.isEmpty)
      #expect(outputs(event) == lines.map(LinkingOutput.line))
      #expect(outputs(event, printsJSON: true).isEmpty)

    }

  }

  // MARK: - Progress

  @Test func notesProgressWithOrWithoutJSON() {

    let notes: [LinkingOutput] = LinkingEventText.notes(for: .identifying(lamp), message: message).map(LinkingOutput.note)

    #expect(!notes.isEmpty)
    #expect(outputs(.identifying(lamp)) == notes)
    #expect(outputs(.identifying(lamp), printsJSON: true) == notes)

  }

  @Test func writesTheLinksMadeAsJSONWhenLinkingFromAHubStops() {

    let result = DeviceLinkingResult(links: [LinkMade(address: lamp, group: 0, mode: .controller)], device: nil, linkBackFailure: nil)
    let event = LinkingEvent.hubLinkingStopped(result, reason: Failure())
    let notes: [LinkingOutput] = LinkingEventText.notes(for: event, message: message).map(LinkingOutput.note)

    #expect(outputs(event, printsJSON: true) == [.json(LinkingJSON.report(result, message: message))] + notes)
    #expect(outputs(event) == notes)

  }

}
