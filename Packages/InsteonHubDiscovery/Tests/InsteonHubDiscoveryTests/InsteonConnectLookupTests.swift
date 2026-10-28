import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubClient
import InsteonHubDiscovery
import InsteonNetworking
import InsteonProtocol

/// Get Info pages modeled on the example in Insteon's support article "Identify Insteon Hub
/// IP Address and Port", and on the page as it reads in 2026, with made-up addresses.
enum GetInfoPage {

  /// A Hub's block as the page shows it in 2026: the address as bold text, and a table of
  /// labels and values.
  static func cardBlock(address: String, insteonID: String) -> String {

    """
    <table width="500" cellpadding="4" cellspacing="0" class="card">
      <tr><td colspan="2" class="title">&#9989; Insteon device was found on your network.<br /><b>\(address)</b> [this is your device's Internal IP]</td></tr>
      <tr><td class="head">Connect Account</td><td class="info">Yes</td></tr>
      <tr><td class="head">Internet IP</td><td class="info">203.0.113.7</td></tr>
      <tr><td class="head">MAC Address</td><td class="info">00:01:23:45:67:89</td></tr>
      <tr><td class="head">Insteon ID</td><td class="info">\(insteonID)</td></tr>
      <tr><td class="head">Subnet Mask</td><td class="info">255.255.252.0</td></tr>
      <tr><td class="head">Gateway</td><td class="info">192.168.4.1</td></tr>
      <tr><td class="head">Device Category</td><td class="info">03</td></tr>
      <tr><td class="head">Sub Category</td><td class="info">33</td></tr>
      <tr><td class="head">Firmware</td><td class="info">1019</td></tr>
      <tr><td class="head">PLM Firmware</td><td class="info">A5</td></tr>
      <tr><td class="head">Unit Type</td><td class="info">HUB2</td></tr>
      <tr><td class="head">Last Heartbeat (UTC)</td><td class="info">10/28/2026 11:22:21 PM</td></tr>
    </table>
    """

  }

  static func hubBlock(link: String, insteonID: String) -> String {

    """
    <table class="hub">
      <tr><td><b>Insteon has been found on your network</b><br/>Click on the Link Below to access Insteon</td></tr>
      <tr><td><a href="\(link)" style="font-size: x-large">\(link)</a><br/>This is your device's internal IP</td></tr>
      <tr><td><b>Other Info</b></td></tr>
      <tr><td>Configured Connect Account</td><td>TRUE</td></tr>
      <tr><td>Your Internet IP:</td><td>203.0.113.7</td></tr>
      <tr><td>Your MAC Address:</td><td>00:0E:F3:00:00:01</td></tr>
      <tr><td>Your Insteon ID</td><td>\(insteonID)</td></tr>
      <tr><td>Your Subnet Mask</td><td>255.255.255.0</td></tr>
      <tr><td>Your Gateway</td><td>10.0.1.1</td></tr>
      <tr><td>Your Device's Unit Type</td><td>HUB2</td></tr>
    </table>
    """

  }

  static func page(_ blocks: String...) -> String {

    "<html><head><title>Insteon - Get Hub Info</title></head><body><h1>Insteon Hub - Get Info</h1>\(blocks.joined())</body></html>"

  }

  static let notFound = page(
    "<p class=\"error\">Sorry, cannot find an Insteon Hub on your network (public IP address 203.0.113.7). Please power cycle your Hub and try again.</p>"
  )

}

struct InsteonConnectLookupTests {

  func makeLookup(answering body: String, status: Int = 200) -> (InsteonConnectLookup, ScriptedHTTPClient) {

    let response = HTTPResponse(statusCode: status, body: Data(body.utf8))
    let client = ScriptedHTTPClient { $0 == "connect.insteon.com" ? response : nil }

    return (InsteonConnectLookup(httpClient: client), client)

  }

  @Test func readsEachHubsAddressAndInsteonID() async throws {

    let (lookup, client) = makeLookup(answering: GetInfoPage.page(
      GetInfoPage.hubBlock(link: "http://10.0.1.10:25105", insteonID: "A0.B1.C2"),
      GetInfoPage.hubBlock(link: "http://10.0.1.11:25105", insteonID: "1A.2B.3C")
    ))

    let hubs = try await lookup.hubs()

    #expect(hubs == [
      DiscoveredHub(endpoint: HubEndpoint(host: "10.0.1.10"), insteonID: InsteonAddress(0xA0, 0xB1, 0xC2)),
      DiscoveredHub(endpoint: HubEndpoint(host: "10.0.1.11"), insteonID: InsteonAddress(0x1A, 0x2B, 0x3C)),
    ])

    let request = try #require(await client.requests.first)

    #expect(request.url?.absoluteString == "https://connect.insteon.com/GetInfo.aspx")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

  }

  @Test func readsTheCardLayout() async throws {

    let (lookup, _) = makeLookup(answering: GetInfoPage.page(
      GetInfoPage.cardBlock(address: "192.168.4.20:25105", insteonID: "1A.2B.3C")
    ))

    // The gateway, 192.168.4.1, is a private address too, but it isn't a Hub.
    #expect(try await lookup.hubs() == [
      DiscoveredHub(endpoint: HubEndpoint(host: "192.168.4.20"), insteonID: InsteonAddress(0x1A, 0x2B, 0x3C)),
    ])

  }

  // Only the well-formed private address is a Hub, and each ID stays with its own card.
  @Test func keepsEachCardsInsteonIDWithItsOwnHub() async throws {

    let (lookup, _) = makeLookup(answering: GetInfoPage.page(
      GetInfoPage.cardBlock(address: "198.51.100.20:25105", insteonID: "A0.B1.C2"),
      GetInfoPage.cardBlock(address: "010.0.0.1:25105", insteonID: "0A.0B.0C"),
      GetInfoPage.cardBlock(address: "192.168.4.20:25105", insteonID: "1A.2B.3C")
    ))

    #expect(try await lookup.hubs() == [
      DiscoveredHub(endpoint: HubEndpoint(host: "192.168.4.20"), insteonID: InsteonAddress(0x1A, 0x2B, 0x3C)),
    ])

  }

  // A line saying no Hub was found doesn't let the next address through without a port.
  @Test func ignoresAnAddressAfterANotFoundLine() async throws {

    let (lookup, _) = makeLookup(answering: GetInfoPage.page(
      "<p>Insteon device was not found on your network.</p><p>192.168.4.1</p>",
      "<p>Sorry, cannot find an Insteon Hub on your network.</p>"
    ))

    #expect(try await lookup.hubs().isEmpty)

  }

  @Test func readsTheCardLayoutWithoutAPort() async throws {

    let (lookup, _) = makeLookup(answering: GetInfoPage.page(
      GetInfoPage.cardBlock(address: "192.168.4.20", insteonID: "1A.2B.3C")
    ))

    #expect(try await lookup.hubs().map(\.endpoint) == [HubEndpoint(host: "192.168.4.20")])

  }

  @Test func readsAPageThatFoundNoHub() async throws {

    let (lookup, _) = makeLookup(answering: GetInfoPage.notFound)

    #expect(try await lookup.hubs().isEmpty)

  }

  // The Hub's password goes to the address, so a public one isn't trusted.
  @Test func skipsAHubListedAtAPublicAddress() async throws {

    let (lookup, _) = makeLookup(answering: GetInfoPage.page(
      GetInfoPage.hubBlock(link: "http://198.51.100.20:25105", insteonID: "A0.B1.C2")
    ))

    #expect(try await lookup.hubs().isEmpty)

  }

  @Test func keepsEachInsteonIDWithItsOwnHub() async throws {

    let (lookup, _) = makeLookup(answering: GetInfoPage.page(
      GetInfoPage.hubBlock(link: "http://10.0.1.10:25105", insteonID: "A0.B1.C2"),
      GetInfoPage.hubBlock(link: "http://198.51.100.20:25105", insteonID: "1A.2B.3C")
    ))

    #expect(try await lookup.hubs().map(\.insteonID) == [InsteonAddress(0xA0, 0xB1, 0xC2)])

  }

  @Test func keepsEachHubOnceAndUsesTheDefaultPort() async throws {

    let (lookup, _) = makeLookup(answering: GetInfoPage.page(
      GetInfoPage.hubBlock(link: "http://10.0.1.10", insteonID: "A0.B1.C2"),
      GetInfoPage.hubBlock(link: "http://10.0.1.10:25105/", insteonID: "A0.B1.C2")
    ))

    #expect(try await lookup.hubs().map(\.endpoint) == [HubEndpoint(host: "10.0.1.10")])

  }

  // Other parsers read a leading zero as octal, so 010.0.0.1 could reach 8.0.0.1, a public
  // address, rather than 10.0.0.1.
  @Test func ignoresALinkWithALeadingZero() async throws {

    let (lookup, _) = makeLookup(answering: GetInfoPage.page(
      GetInfoPage.hubBlock(link: "http://010.0.0.1:25105", insteonID: "A0.B1.C2"),
      GetInfoPage.hubBlock(link: "http://10.0.1.11:25105", insteonID: "1A.2B.3C")
    ))

    #expect(try await lookup.hubs().map(\.endpoint.host) == ["10.0.1.11"])

  }

  @Test func readsHubsEvenWhenThePageAlsoSaysItFoundNone() async throws {

    let (lookup, _) = makeLookup(answering: GetInfoPage.page(
      "<div style=\"display: none\">Sorry, cannot find an Insteon Hub on your network.</div>",
      GetInfoPage.hubBlock(link: "http://10.0.1.10:25105", insteonID: "A0.B1.C2")
    ))

    #expect(try await lookup.hubs().count == 1)

  }

  @Test func reportsAPageItCantRead() async throws {

    let (lookup, _) = makeLookup(answering: "<html><body>Please sign in</body></html>")

    await #expect(throws: InsteonConnectError.unrecognizedPage) {

      try await lookup.hubs()

    }

  }

  @Test func reportsAnErrorStatus() async throws {

    let (lookup, _) = makeLookup(answering: "", status: 503)

    await #expect(throws: InsteonConnectError.unexpectedStatus(503)) {

      try await lookup.hubs()

    }

  }

}
