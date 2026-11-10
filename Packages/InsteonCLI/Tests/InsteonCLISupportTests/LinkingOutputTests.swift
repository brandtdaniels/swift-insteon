import Testing
import InsteonCLISupport
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// What `insteon link`, `unlink` and `remove` do with each event a coordinator reports: what
/// they save, print or write as JSON.
struct LinkingOutputTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  struct Failure: Error {}

  let message: (any Error) -> String = { (_: any Error) -> String in "It failed." }

  /// A made-up catalog with the lamp's product.
  let catalog = DeviceCatalog(profiles: [
    DeviceProfile(
      model: "9402",
      name: "Example Linked Lamp",
      identities: [DeviceIdentity(category: 0x01, subcategory: 0x2C)],
      groups: [DeviceProfile.Group(number: 1, name: "Load", role: .responder)]
    )
  ])

  var registered: RegisteredDevice {

    RegisteredDevice(
      address: lamp,
      identity: ReportedIdentity(category: 0x01, subcategory: 0x2C, firmwareVersion: 0x45),
      info: DeviceInfo(catalog.describe(category: 0x01, subcategory: 0x2C, firmwareVersion: 0x45))
    )

  }

  func outputs(_ event: LinkingEvent, printsJSON: Bool = false, namesProducts: Bool = true) -> [LinkingOutput] {

    LinkingOutput.outputs(for: event, printsJSON: printsJSON, namesProducts: namesProducts, message: message)

  }

  // MARK: - A link made

  @Test func savesTheIdentityAndPrintsItWithTheFirstLink() {

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

  @Test func leavesOutTheProductWithoutACatalogAndSaysWhatsNotReported() {

    let made = LinkMade(address: lamp, group: 1, mode: .controller)
    let unreported = RegisteredDevice(address: lamp, identity: ReportedIdentity(category: 0x01, subcategory: 0x2C, firmwareVersion: nil), info: DeviceInfo(catalog.describe(category: 0x01, subcategory: 0x2C, firmwareVersion: nil)))
    let found = outputs(.linked(LinkedDevice(link: made, device: unreported, leg: .first)), namesProducts: false)

    guard case let .table(rows)? = found.last else {

      Issue.record("Expected a table, got \(found).")

      return

    }

    #expect(rows.map { (row: [String]) -> String? in row.first } == ["Category:", "Subcategory:", "Firmware:"])
    #expect(rows.last?.last == "not reported")

  }

  @Test func printsTheLinkBackAloneAndSavesNothingThen() {

    let back = LinkMade(address: lamp, group: 1, mode: .responder)

    #expect(outputs(.linked(LinkedDevice(link: back, device: registered, leg: .linkBack))) == [
      .line("Linked 1A.2B.3C in group 1, modem as \(Names.mode(back.mode)).")
    ])

  }

  @Test func onlySavesTheIdentityWithJSON() {

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

  @Test func printsEachLinkRemovedWithoutTheSETButtonOrThatThereWereNone() {

    let label: String = LinkingInstructions.deviceLabel(lamp, info: registered.info)
    let removed = RemovedLinks(address: lamp, device: registered, links: [ModemLink(modemRole: .responder, group: 1), ModemLink(modemRole: .controller, group: 0)])
    let lines: [LinkingOutput] = LinkingJSON.removedLinks(removed).map { (link: LinkingJSON.RemovedLink) -> LinkingOutput in

      .line("Unlinked \(label) from group \(link.group), modem as \(link.modemRole).")

    }

    #expect(outputs(.unlinkedAll(removed)) == lines)
    #expect(lines.count == 2)
    #expect(outputs(.unlinkedAll(RemovedLinks(address: lamp, device: registered, links: []))) == [.line("The modem has no links with \(label).")])

  }

  @Test func printsADeviceForgottenOnlyWithoutJSON() {

    let forgotten = ForgottenDevice(address: lamp, device: registered)

    #expect(outputs(.forgotten(forgotten)) == RemovalText.forgotten(forgotten).map(LinkingOutput.line))
    #expect(outputs(.forgotten(forgotten), printsJSON: true).isEmpty)

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
