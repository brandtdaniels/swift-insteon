import Foundation
import Testing
import InsteonProtocol

struct ReportedIdentityTests {

  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  let plug = ReportedIdentity(category: 0x02, subcategory: 0x7A, firmwareVersion: 0x41)

  @Test func readsTheIdentityFromSETButtonPressed() {

    let pressed = SetButtonPressed(sender: device, role: .responder, category: 0x02, subcategory: 0x7A, firmwareVersion: 0x41)

    #expect(ReportedIdentity(pressed) == plug)

  }

  @Test func readsAnIdentityFromALinkOnlyWhenTheModemReportedOne() {

    let controller = AllLinkingCompleted(linkCode: 0x01, group: 0, address: device, category: 0x02, subcategory: 0x7A, firmwareVersion: 0x41)
    let responder = AllLinkingCompleted(linkCode: 0x00, group: 1, address: device, category: nil, subcategory: nil, firmwareVersion: nil)

    #expect(ReportedIdentity(controller) == plug)
    #expect(ReportedIdentity(responder) == nil)

  }

  @Test func readsTheIdentityFromBroadcastsAndTheModemsInfo() {

    let heartbeat = Heartbeat(sender: device, batteryLevel: 0xFF, category: 0x10, subcategory: 0x08, firmwareVersion: nil)
    let status = DeviceStatusChanged(sender: device, category: 0x02, subcategory: 0x7A, firmwareVersion: 0x41)
    let info = ModemInfo(address: device, category: 0x03, subcategory: 0x33, firmwareVersion: 0x9E)

    #expect(ReportedIdentity(heartbeat) == ReportedIdentity(category: 0x10, subcategory: 0x08, firmwareVersion: nil))
    #expect(ReportedIdentity(status) == plug)
    #expect(ReportedIdentity(info) == ReportedIdentity(category: 0x03, subcategory: 0x33, firmwareVersion: 0x9E))

  }

  @Test func encodesItsBytesInHexadecimal() throws {

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let json: String = String(decoding: try encoder.encode(plug), as: UTF8.self)

    #expect(json == #"{"category":"0x02","firmwareVersion":"0x41","subcategory":"0x7A"}"#)

    let noVersion = ReportedIdentity(category: 0x01, subcategory: 0x20, firmwareVersion: nil)
    let shortJSON: String = String(decoding: try encoder.encode(noVersion), as: UTF8.self)

    #expect(shortJSON == #"{"category":"0x01","subcategory":"0x20"}"#)

  }

  @Test func decodesWhatItEncodes() throws {

    let noVersion = ReportedIdentity(category: 0x01, subcategory: 0x20, firmwareVersion: nil)

    for identity in [plug, noVersion] {

      let data: Data = try JSONEncoder().encode(identity)

      #expect(try JSONDecoder().decode(ReportedIdentity.self, from: data) == identity)

    }

    let lowercase = Data(#"{"category":"0x02","subcategory":"0x7a","firmwareVersion":null}"#.utf8)
    let decoded: ReportedIdentity = try JSONDecoder().decode(ReportedIdentity.self, from: lowercase)

    #expect(decoded == ReportedIdentity(category: 0x02, subcategory: 0x7A, firmwareVersion: nil))

  }

  @Test(arguments: [
    #"{"category":"2","subcategory":"0x7A"}"#,
    #"{"category":"0x002","subcategory":"0x7A"}"#,
    #"{"category":"0xZZ","subcategory":"0x7A"}"#,
    #"{"subcategory":"0x7A"}"#,
    #"{"category":"0x02","subcategory":"0x7A","firmwareVersion":"41"}"#
  ])
  func rejectsBytesThatArentWrittenAsHexadecimal(_ json: String) {

    #expect(throws: DecodingError.self) {

      try JSONDecoder().decode(ReportedIdentity.self, from: Data(json.utf8))

    }

  }

}
