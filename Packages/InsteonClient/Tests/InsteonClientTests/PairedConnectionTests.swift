import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonClient
import InsteonNetworking
import InsteonService
import Testing

private let token = "tok-7c21-invented"

private func document(routes: String) -> Data {
  Data(#"{"version":1,"serviceId":"svc-1","name":"Example Home","credential":"\#(token)","scope":"control","api":"/api/v1","routes":\#(routes),"futureField":true}"#.utf8)
}

private let healthy = json(#"{"version":1,"status":"ready","modem":{"connected":true,"cause":null}}"#)
private let oneDevice = json(#"{"version":1,"devices":[{"address":"1A.2B.3C","productName":"Example Dimmer","canTurnOnAndOff":true,"canDim":true,"value":1,"lastAnsweredAt":null}],"stale":false,"cause":null}"#)

/// Opens a route to a local forwarding address, as a transport plugin does.
struct ForwardingOpener: RouteOpening {
  let kind: String
  let forwardTo: URL?
  func open(ticket: String?) async throws -> URL {
    guard let forwardTo else { throw Unplugged() }
    return forwardTo
  }
}

@Suite("A pairing document becomes a connection", .timeLimit(.minutes(1)))
struct PairedConnectionTests {

  @Test func theDocumentIsReadAndUnknownFieldsAreIgnored() throws {
    let pairing = try ClientPairing(decoding: document(routes: #"[{"kind":"lan","url":"http://192.0.2.20:8080"}]"#))

    #expect(pairing.name == "Example Home")
    #expect(pairing.serviceID == "svc-1")
    #expect(pairing.scope == "control")
    #expect(pairing.routes == [ClientPairing.Route(kind: "lan", url: "http://192.0.2.20:8080", ticket: nil)])
  }

  @Test func aDocumentOfAnotherVersionIsRefused() {
    let data = Data(#"{"version":2,"serviceId":"s","name":"n","credential":"c","scope":"read","api":"/api/v1","routes":[]}"#.utf8)

    #expect(throws: ClientPairing.Failure.unsupportedVersion(2)) { try ClientPairing(decoding: data) }
  }

  @Test func aDocumentThatIsNotOneIsRefused() {
    #expect(throws: ClientPairing.Failure.unreadable) { try ClientPairing(decoding: Data("not json".utf8)) }
  }

  @Test func aPairingDescriptionHidesTheCredential() throws {
    let pairing = try ClientPairing(decoding: document(routes: "[]"))

    #expect(!String(describing: pairing).contains(token))
    #expect(!String(reflecting: pairing).contains(token))
  }

  @Test func routesAreTriedInTheDocumentsOrderAfterTheLocalPath() async throws {
    let pairing = try ClientPairing(decoding: document(routes: #"[{"kind":"lan","url":"http://192.0.2.20:8080"},{"kind":"example-transport","ticket":"t1"}]"#))
    let http = FakeHTTPClient { request in
      switch (request.url?.host, request.url?.path) {
      case ("192.0.2.20", _): throw Unplugged()
      case (_, "/api/v1/health"): return healthy
      default: return oneDevice
      }
    }
    let local = ScriptedPath("local", openings: [.notReached("no Hub answered")])
    let home = HomeConnection(
      pairing: pairing,
      local: local,
      routeOpeners: [ForwardingOpener(kind: "example-transport", forwardTo: URL(string: "http://127.0.0.1:9100")!)],
      http: http
    )

    let devices = try await home.devices()

    #expect(devices.count == 1)
    #expect(await local.openCount == 1)
    #expect(await home.currentPath == "example-transport")
    let lines = await http.lines
    #expect(lines == [
      "GET http://192.0.2.20:8080/api/v1/health",
      "GET http://127.0.0.1:9100/api/v1/health",
      "GET http://127.0.0.1:9100/api/v1/devices"
    ])
  }

  @Test func aRouteKindNoOpenerKnowsIsSkipped() async throws {
    let pairing = try ClientPairing(decoding: document(routes: #"[{"kind":"mystery","ticket":"x"},{"kind":"lan","url":"http://192.0.2.20:8080"}]"#))
    let http = FakeHTTPClient { request in request.url?.path == "/api/v1/health" ? healthy : oneDevice }
    let home = HomeConnection(pairing: pairing, local: nil, routeOpeners: [], http: http)

    _ = try await home.devices()

    #expect(await home.currentPath == "lan")
  }

  @Test func aTransportThatCannotOpenIsNotReachedAndTheNextRouteIsTried() async throws {
    let pairing = try ClientPairing(decoding: document(routes: #"[{"kind":"example-transport","ticket":"t1"},{"kind":"lan","url":"http://192.0.2.20:8080"}]"#))
    let http = FakeHTTPClient { request in request.url?.path == "/api/v1/health" ? healthy : oneDevice }
    let home = HomeConnection(pairing: pairing, local: nil, routeOpeners: [ForwardingOpener(kind: "example-transport", forwardTo: nil)], http: http)

    _ = try await home.devices()

    #expect(await home.currentPath == "lan")
  }

  @Test func theSameTokenGoesToEveryRoute() async throws {
    let pairing = try ClientPairing(decoding: document(routes: #"[{"kind":"example-transport","ticket":"t1"}]"#))
    let http = FakeHTTPClient { request in request.url?.path == "/api/v1/health" ? healthy : oneDevice }
    let home = HomeConnection(pairing: pairing, local: nil, routeOpeners: [ForwardingOpener(kind: "example-transport", forwardTo: URL(string: "http://127.0.0.1:9100")!)], http: http)

    _ = try await home.devices()

    for request in await http.requests {
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + token)
    }
  }

  @Test func routesThatAreLeftOutAreReportedWithTheirReasonWhenNothingIsReached() async throws {
    let pairing = try ClientPairing(decoding: document(routes: #"[{"kind":"mystery","ticket":"x"},{"kind":"lan","url":"not a url"},{"kind":"lan"},{"kind":"lan","url":"http://home.example.com:8080"}]"#))
    let http = FakeHTTPClient { _ in healthy }
    let home = HomeConnection(pairing: pairing, local: nil, routeOpeners: [], http: http)

    await #expect(throws: HomeError.noPathReached([
      PathFailure(path: "mystery", reason: "this device has no transport for the mystery route"),
      PathFailure(path: "lan", reason: "the route has no usable address"),
      PathFailure(path: "lan", reason: "the route has no usable address"),
      PathFailure(path: "lan", reason: "the token is never sent over HTTP to a host outside the local network")
    ])) { _ = try await home.devices() }
    #expect(await http.requests.isEmpty)
  }

  @Test func plainHTTPIsAllowedOnlyToTheLocalNetwork() async throws {
    let local = ["http://127.0.0.1:8080", "http://localhost:8080", "http://insteon.local:8080", "http://insteon:8080", "http://10.1.2.3", "http://192.168.1.5", "http://172.16.0.1", "http://172.31.255.1", "http://169.254.1.1", "http://[::1]:8080", "http://192.0.2.20:8080", "http://[fe80::1]:8080", "http://[fd00::1]:8080"]
    let remote = ["http://home.example.com", "http://8.8.8.8", "http://172.32.0.1", "http://[2001:4860::1]:8080"]
    for address in local + remote {
      let http = FakeHTTPClient { request in request.url?.path == "/api/v1/health" ? healthy : oneDevice }
      let pairing = try ClientPairing(decoding: document(routes: #"[{"kind":"lan","url":"\#(address)"}]"#))
      let home = HomeConnection(pairing: pairing, routeOpeners: [], http: http)

      let reached = (try? await home.devices()) != nil

      #expect(reached == local.contains(address), "\(address)")
    }
  }

  @Test func httpsIsAllowedToAnyHost() async throws {
    let http = FakeHTTPClient { request in request.url?.path == "/api/v1/health" ? healthy : oneDevice }
    let pairing = try ClientPairing(decoding: document(routes: #"[{"kind":"lan","url":"https://home.example.com"}]"#))

    _ = try await HomeConnection(pairing: pairing, routeOpeners: [], http: http).devices()
  }
}
