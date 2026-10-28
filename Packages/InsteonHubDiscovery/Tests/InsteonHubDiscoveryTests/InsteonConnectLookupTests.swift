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
/// IP Address and Port", with made-up addresses. A captured page would make a better fixture.
enum GetInfoPage {

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
