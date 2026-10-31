import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// The JSON `insteon link --json` and `insteon unlink --json` print, which scripts read key by
/// key.
struct LinkingJSONTests {

  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  let identity = ReportedIdentity(category: 0x01, subcategory: 0x5A, firmwareVersion: 0x41)

  /// A made-up catalog with the lamp's product.
  let catalog = DeviceCatalog(profiles: [
    DeviceProfile(
      model: "9201",
      name: "Example Lamp Dimmer",
      identities: [DeviceIdentity(category: 0x01, subcategory: 0x5A)],
      groups: [DeviceProfile.Group(number: 1, name: "Load", role: .controller)]
    )
  ])

  /// The lamp as the registry knows it.
  var registered: RegisteredDevice {

    RegisteredDevice(
      address: lamp,
      identity: identity,
      deviceDescription: catalog.describe(category: 0x01, subcategory: 0x5A, firmwareVersion: 0x41)
    )

  }

  /// The product's name, as the catalog writes it.
  var product: String {

    registered.deviceDescription.displayName ?? ""

  }

  /// Encodes a value with its keys sorted, on one line.
  func encoded(_ value: some Encodable) throws -> String {

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    return String(decoding: try encoder.encode(value), as: UTF8.self)

  }

  @Test func printsOneLinkInTheSameObjectWithNoLegs() throws {

    let made = AllLinkingCompleted(linkCode: 0x01, group: 0, address: lamp, category: nil, subcategory: nil, firmwareVersion: nil)
    let result = DeviceLinkingResult(links: [made], device: registered, linkBackFailure: nil)

    #expect(try encoded(LinkingJSON.report(result)) == """
      {"legs":[],"links":[{"address":"1A.2B.3C","category":"0x01","firmwareVersion":"0x41","group":0,"modemRole":"controller",\
      "product":"\(product)","subcategory":"0x5A"}]}
      """)

  }

  @Test func printsALinkBackInTheSameObject() throws {

    let made = AllLinkingCompleted(linkCode: 0x01, group: 0, address: lamp, category: nil, subcategory: nil, firmwareVersion: nil)
    let back = AllLinkingCompleted(linkCode: 0x00, group: 1, address: lamp, category: nil, subcategory: nil, firmwareVersion: nil)
    let result = DeviceLinkingResult(links: [made, back], device: nil, linkBackFailure: nil)

    // A device whose identity isn't known has no category, subcategory, firmware or product.
    #expect(try encoded(LinkingJSON.report(result)) == """
      {"legs":[],"links":[{"address":"1A.2B.3C","group":0,"modemRole":"controller"},{"address":"1A.2B.3C","group":1,"modemRole":"responder"}]}
      """)

  }

  @Test func printsTheLinksUnlinkAllRemovedAsAnArray() throws {

    let removed = RemovedLinks(
      address: lamp,
      device: registered,
      links: [ModemLink(modemRole: .responder, group: 1), ModemLink(modemRole: .controller, group: 0)]
    )

    #expect(try encoded(LinkingJSON.removedLinks(removed)) == """
      [{"address":"1A.2B.3C","group":1,"modemRole":"responder","product":"\(product)"},\
      {"address":"1A.2B.3C","group":0,"modemRole":"controller","product":"\(product)"}]
      """)
    #expect(try encoded(LinkingJSON.removedLinks(RemovedLinks(address: lamp, device: nil, links: []))) == "[]")

  }

  @Test func printsAnUnlinkWithTheProductWhenItsKnown() throws {

    let removed = AllLinkingCompleted(linkCode: 0xFF, group: 3, address: lamp, category: nil, subcategory: nil, firmwareVersion: nil)

    #expect(try encoded(LinkingJSON.unlink(UnlinkedLink(link: removed, device: registered))) == """
      {"address":"1A.2B.3C","group":3,"product":"\(product)"}
      """)
    #expect(try encoded(LinkingJSON.unlink(UnlinkedLink(link: removed, device: nil))) == """
      {"address":"1A.2B.3C","group":3}
      """)

  }

  @Test func printsTheLegsWithTheirLinks() throws {

    let made = AllLinkingCompleted(linkCode: 0x01, group: 0, address: lamp, category: nil, subcategory: nil, firmwareVersion: nil)
    let first = HubLinkingLeg(device: lamp, index: 0, count: 3, modemRole: .controller, modemGroup: 0, deviceGroup: 1)
    let second = HubLinkingLeg(device: lamp, index: 1, count: 3, modemRole: .responder, modemGroup: 1, deviceGroup: 1)
    let third = HubLinkingLeg(device: lamp, index: 2, count: 3, modemRole: .responder, modemGroup: 2, deviceGroup: 2)
    let result = DeviceLinkingResult(
      links: [made],
      device: nil,
      linkBackFailure: nil,
      legs: [
        HubLinkingLegOutcome(leg: first, status: .linked(made, by: .enterLinkingMode)),
        HubLinkingLegOutcome(leg: second, status: .failed(LinkingError.linkingTimedOut)),
        HubLinkingLegOutcome(leg: third, status: .notRun)
      ]
    )

    let report: LinkingJSON.LinkReport = LinkingJSON.report(result, message: { (_: any Error) -> String in "It failed." })

    #expect(try encoded(report) == """
      {"legs":[{"deviceGroup":1,"joinedBy":"enterLinkingMode","modemGroup":0,"modemRole":"controller","status":"linked"},\
      {"deviceGroup":1,"error":"It failed.","modemGroup":1,"modemRole":"responder","status":"failed"},\
      {"deviceGroup":2,"modemGroup":2,"modemRole":"responder","status":"notRun"}],\
      "links":[{"address":"1A.2B.3C","group":0,"modemRole":"controller"}]}
      """)

  }

}
