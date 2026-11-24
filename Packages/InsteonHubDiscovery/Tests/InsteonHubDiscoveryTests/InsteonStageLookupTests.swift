import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonHubClient
import InsteonHubDiscovery
import InsteonNetworking
import InsteonProtocol

/// A card as Insteon's staging service lists a Hub Pro, with made-up values: its address ends
/// in the port, and its firmware reads as two versions.
private let hubProCard = """
  <table width="500" cellpadding="4" cellspacing="0" class="card">
    <tr><td colspan="2" class="title">&#9989; Insteon device was found on your network.<br /><b>192.168.1.50:80</b> [this is your device's Internal IP]</td></tr>
    <tr><td class="head">Connect Account</td><td class="info">No</td></tr>
    <tr><td class="head">Internet IP</td><td class="info">203.0.113.7</td></tr>
    <tr><td class="head">MAC Address</td><td class="info">00:01:23:45:67:89</td></tr>
    <tr><td class="head">Insteon ID</td><td class="info">4D.5E.6F</td></tr>
    <tr><td class="head">Subnet Mask</td><td class="info">255.255.255.0</td></tr>
    <tr><td class="head">Gateway</td><td class="info">192.168.1.1</td></tr>
    <tr><td class="head">Device Category</td><td class="info">03</td></tr>
    <tr><td class="head">Sub Category</td><td class="info">3A</td></tr>
    <tr><td class="head">Firmware</td><td class="info">s:1.0.2-stage|c:5.0.1</td></tr>
    <tr><td class="head">PLM Firmware</td><td class="info">9D</td></tr>
    <tr><td class="head">App Version</td><td class="info">HubPro-V02</td></tr>
    <tr><td class="head">Unit Type</td><td class="info">HubPro</td></tr>
    <tr><td class="head">Last Heartbeat (UTC)</td><td class="info">10/28/2026 11:22:21 PM</td></tr>
    <tr><td class="head">Connected Home Access</td><td class="info">No</td></tr>
    <tr><td class="head">Home Access Ends (UTC)</td><td class="info"></td></tr>
  </table>
  """

@Suite(.timeLimit(.minutes(1)))
struct InsteonStageLookupTests {

  func makeLookup(host: String, answering body: String, pageURL: URL) -> (InsteonConnectLookup, ScriptedHTTPClient) {

    let response = HTTPResponse(statusCode: 200, body: Data(body.utf8))
    let client = ScriptedHTTPClient { $0 == host ? response : nil }

    return (InsteonConnectLookup(pageURL: pageURL, httpClient: UnauthenticatedHTTPClient(transport: client)), client)

  }

  @Test func asksTheStagingPageWhenGivenItsAddress() async throws {

    let (lookup, client) = makeLookup(host: "sfstage.insteon.com", answering: GetInfoPage.page(hubProCard), pageURL: InsteonConnectLookup.stagingPageURL)

    _ = try await lookup.hubs()

    let requests = await client.requests

    #expect(requests.compactMap(\.url?.absoluteString) == ["https://sfstage.insteon.com/GetInfo.aspx"])
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    #expect(requests.allSatisfy { $0.httpMethod == "GET" || $0.httpMethod == nil })

  }

  @Test func readsAHubProsCardWithItsUnitTypeAndFirmware() async throws {

    let (lookup, _) = makeLookup(host: "sfstage.insteon.com", answering: GetInfoPage.page(hubProCard), pageURL: InsteonConnectLookup.stagingPageURL)

    #expect(try await lookup.hubs() == [
      DiscoveredHub(
        endpoint: HubEndpoint(host: "192.168.1.50", port: 80),
        insteonID: InsteonAddress(0x4D, 0x5E, 0x6F),
        category: 0x03,
        subcategory: 0x3A,
        modemFirmwareVersion: 0x9D,
        unitType: "HubPro",
        firmware: "s:1.0.2-stage|c:5.0.1",
        kind: .hubPro
      ),
    ])

  }

  @Test func asksProductionByDefault() async throws {

    let (lookup, client) = makeLookup(host: "connect.insteon.com", answering: GetInfoPage.notFound, pageURL: InsteonConnectLookup.pageURL)

    #expect(try await lookup.hubs().isEmpty)
    #expect(await client.requests.compactMap(\.url?.absoluteString) == ["https://connect.insteon.com/GetInfo.aspx"])
    #expect(InsteonConnectLookup().url == InsteonConnectLookup.pageURL)

  }

  @Test func aHubKeepsTheHubKindAndAHubUnitTypeIsNotAHubPro() async throws {

    let (lookup, _) = makeLookup(
      host: "connect.insteon.com",
      answering: GetInfoPage.page(GetInfoPage.cardBlock(address: "192.168.4.20:25105", insteonID: "1A.2B.3C")),
      pageURL: InsteonConnectLookup.pageURL
    )

    #expect(try await lookup.hubs().map(\.kind) == [.hub])

  }

  @Test func namesTheStagingServiceAsASource() {

    #expect(DiscoverySource.allCases.contains(.insteonStage))

  }

}
