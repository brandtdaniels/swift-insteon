import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import InsteonClient
import InsteonCore
import InsteonNetworking
import InsteonProtocol
import InsteonService
import Testing

private let token = "tok-3f9a0c-invented"
private let base = URL(string: "http://192.0.2.20:8080")!

private let healthy = json(#"{"version":1,"status":"ready","modem":{"connected":true,"cause":null}}"#)
private let deviceList = json(#"{"version":1,"devices":[{"address":"1A.2B.3C","productName":"Example Dimmer","canTurnOnAndOff":true,"canDim":true,"value":128,"lastAnsweredAt":"2026-11-25T10:00:00Z"},{"address":"4D.5E.6F","productName":null,"canTurnOnAndOff":false,"canDim":false,"value":null,"lastAnsweredAt":null}],"stale":false,"cause":null}"#)

/// What the service answers a refused request with: its full error shape.
private func refusal(_ code: String, sent: Bool, cause: String? = nil, status: Int) -> HTTPResponse {
  let cause = cause.map { ",\"cause\":\"\($0)\"" } ?? ""
  return json(#"{"version":1,"code":"\#(code)","message":"Refused.","sent":\#(sent),"requestId":"r-1"\#(cause)}"#, status: status)
}

private func calls(_ http: FakeHTTPClient) async throws -> any ConnectionCalls {
  try await ServicePath(name: "lan", baseURL: base, token: token, http: http).open()
}

@Suite("ServicePath speaks the service's HTTP contract", .timeLimit(.minutes(1)))
struct ServicePathTests {

  @Test func openingAsksHealthWithTheBearerToken() async throws {
    let http = FakeHTTPClient { _ in healthy }

    _ = try await calls(http)

    #expect(await http.lines == ["GET http://192.0.2.20:8080/api/v1/health"])
    #expect(await http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer " + token)
  }

  @Test func aServiceThatDoesNotAnswerIsNotReached() async {
    let http = FakeHTTPClient { _ in throw Unplugged() }

    await #expect(throws: ConnectionPathError.notReached("the service didn't answer")) { _ = try await calls(http) }
  }

  @Test func aServerErrorOnHealthIsNotReached() async {
    let http = FakeHTTPClient { _ in json("{}", status: 503) }

    await #expect(throws: ConnectionPathError.notReached("the service answered with status 503")) { _ = try await calls(http) }
  }

  @Test func aRefusedTokenIsUnauthorizedAndAScopeTooLowIsForbidden() async {
    let refused = FakeHTTPClient { _ in refusal("authenticationFailed", sent: false, status: 401) }
    await #expect(throws: ConnectionPathError.unauthorized) { _ = try await calls(refused) }
    let tooLow = FakeHTTPClient { _ in refusal("forbidden", sent: false, status: 403) }
    await #expect(throws: ConnectionPathError.forbidden) { _ = try await calls(tooLow) }
  }

  @Test func devicesAreDecodedFromTheListing() async throws {
    let http = FakeHTTPClient { request in request.url?.path == "/api/v1/health" ? healthy : deviceList }

    let devices = try await calls(http).devices()

    #expect(devices.count == 2)
    #expect(devices[0].address == lampAddress)
    #expect(devices[0].productName == "Example Dimmer")
    #expect(devices[0].canDim && devices[0].canTurnOnAndOff)
    #expect(devices[0].value == 128)
    #expect(devices[0].lastAnsweredAt == ISO8601DateFormatter().date(from: "2026-11-25T10:00:00Z"))
    #expect(devices[1].productName == nil && devices[1].value == nil && devices[1].lastAnsweredAt == nil)
  }

  @Test func aLostConnectionDuringAReadIsInterrupted() async throws {
    let calls = try await calls(FakeHTTPClient { request in
      if request.url?.path == "/api/v1/health" { return healthy }
      throw Unplugged()
    })

    await #expect(throws: ConnectionPathError.interrupted) { _ = try await calls.devices() }
  }

  @Test func aCommandLostAfterItWasSentIsInterruptedNeverNotReached() async throws {
    let c = try await calls(FakeHTTPClient { request in
      if request.url?.path == "/api/v1/health" { return healthy }
      throw Unplugged()
    })

    await #expect(throws: ConnectionPathError.interrupted) { _ = try await c.execute(ServiceCommand(address: lampAddress, action: .on)) }
  }

  @Test func aCommandIsPostedAsJSONWithTheMarkerAndNoRepeatKey() async throws {
    let http = FakeHTTPClient { request in
      request.url?.path == "/api/v1/health" ? healthy : json(#"{"version":1,"address":"1A.2B.3C","outcome":"acknowledged","status":null,"persistence":"saved"}"#)
    }

    let receipt = try await calls(http).execute(ServiceCommand(address: lampAddress, action: .on, levelPercent: 50))

    #expect(receipt == CommandReceipt(address: lampAddress, outcome: .acknowledged, status: nil, persistence: .saved))
    let request = try #require(await http.requests.last)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/v1/devices/1A.2B.3C/commands")
    #expect(request.value(forHTTPHeaderField: "X-Insteon-Request") == "1")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let body = try #require(request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    #expect(body["action"] as? String == "on")
    #expect(body["levelPercent"] as? Int == 50)
  }

  @Test func theAddressInTheCommandPathIsTwoUppercaseHexDigitsPerByteWithDots() async throws {
    let http = FakeHTTPClient { request in
      request.url?.path == "/api/v1/health" ? healthy : json(#"{"version":1,"address":"01.0A.FF","outcome":"acknowledged","status":null,"persistence":"saved"}"#)
    }

    _ = try await calls(http).execute(ServiceCommand(address: InsteonAddress(0x01, 0x0A, 0xFF), action: .off))

    #expect(await http.requests.last?.url?.path == "/api/v1/devices/01.0A.FF/commands")
  }

  @Test func aStatusReadComesBackWithItsReading() async throws {
    let http = FakeHTTPClient { request in
      request.url?.path == "/api/v1/health" ? healthy : json(#"{"version":1,"address":"1A.2B.3C","outcome":"read","status":{"group":1,"kind":"percent","value":128,"isOn":true,"percent":50,"label":null},"persistence":"notConfigured"}"#)
    }

    let receipt = try await calls(http).execute(ServiceCommand(address: lampAddress, action: .status))

    #expect(receipt.outcome == .read)
    #expect(receipt.status?.reading == .percent(50))
    #expect(receipt.status?.value == 128)
    #expect(receipt.status?.isOn == true)
    #expect(receipt.status?.group == 1)
  }

  @Test func theServicesRefusalsBecomeTheServiceControlErrorsTheyAre() async throws {
    let table: [(String, ServiceControlError)] = [
      ("unknownDevice", .unknownDevice), ("invalidLevel", .invalidLevel), ("unsupportedControl", .unsupportedControl),
      ("notIdentified", .notIdentified), ("notLinked", .notLinked), ("busy", .busy)
    ]
    for (code, expected) in table {
      let c = try await calls(FakeHTTPClient { request in
        request.url?.path == "/api/v1/health" ? healthy : refusal(code, sent: false, status: 409)
      })
      await #expect(throws: expected) { _ = try await c.execute(ServiceCommand(address: lampAddress, action: .on)) }
    }
  }

  @Test func aModemThatIsAwayKeepsItsCause() async throws {
    let c = try await calls(FakeHTTPClient { request in
      request.url?.path == "/api/v1/health" ? healthy : refusal("modemUnavailable", sent: false, cause: "hubUnreachable", status: 503)
    })

    await #expect(throws: ServiceControlError.modemUnavailable(.hubUnreachable)) { _ = try await c.execute(ServiceCommand(address: lampAddress, action: .on)) }
  }

  @Test func anyOtherRefusalKeepsItsCodeAndWhetherTheCommandMayHaveBeenSent() async throws {
    let c = try await calls(FakeHTTPClient { request in
      request.url?.path == "/api/v1/health" ? healthy : refusal("outcomeUnknown", sent: true, status: 502)
    })

    await #expect(throws: ConnectionError.rejected(code: "outcomeUnknown", sent: true)) { _ = try await c.execute(ServiceCommand(address: lampAddress, action: .on)) }
  }

  @Test func aTokenNeverAppearsInADescriptionOrAnError() async throws {
    let path = ServicePath(name: "lan", baseURL: base, token: token, http: FakeHTTPClient { _ in throw Unplugged() })

    #expect(!String(describing: path).contains(token))
    #expect(!String(reflecting: path).contains(token))
    do { _ = try await path.open() } catch {
      #expect(!String(describing: error).contains(token))
      #expect(!String(reflecting: error).contains(token))
    }
  }

  @Test func aCredentialRefusedOnACallIsUnauthorizedAndAScopeTooLowIsForbidden() async throws {
    for (status, expected) in [(401, ConnectionPathError.unauthorized), (403, ConnectionPathError.forbidden)] {
      let c = try await calls(FakeHTTPClient { request in
        request.url?.path == "/api/v1/health" ? healthy : refusal("authenticationFailed", sent: false, status: status)
      })
      await #expect(throws: expected) { _ = try await c.devices() }
      await #expect(throws: expected) { _ = try await c.execute(ServiceCommand(address: lampAddress, action: .on)) }
    }
  }

  @Test func cancellationWhileOpeningIsNotAPathFailure() async {
    let http = FakeHTTPClient { _ in throw CancellationError() }

    await #expect(throws: CancellationError.self) { _ = try await calls(http) }
  }

  @Test func cancellationInsideATransportOpenerIsNotAPathFailureEither() async throws {
    let pairing = try ClientPairing(decoding: Data(#"{"version":1,"serviceId":"s","name":"n","credential":"c","scope":"read","api":"/api/v1","routes":[{"kind":"example-transport","ticket":"t"}]}"#.utf8))
    let connection = ClientConnection(pairing: pairing, routeOpeners: [CancelingOpener()], http: FakeHTTPClient { _ in healthy })

    await #expect(throws: CancellationError.self) { _ = try await connection.devices() }
  }

  @Test func aBodyThatOnlyLooksLikeARefusalIsNotOne() async throws {
    let lookAlikes = [#"{"code":"busy"}"#, #"{"code":"busy","sent":false}"#, #"{"version":2,"code":"busy","message":"m","sent":false,"requestId":"r"}"#, #"{"version":1,"code":"busy","message":"m","requestId":"r"}"#]
    for body in lookAlikes {
      for (status, expected) in [(409, ConnectionPathError.badResponse), (503, ConnectionPathError.interrupted)] {
        let c = try await calls(FakeHTTPClient { request in request.url?.path == "/api/v1/health" ? healthy : json(body, status: status) })

        await #expect(throws: expected, "\(body) \(status)") { _ = try await c.execute(ServiceCommand(address: lampAddress, action: .on)) }
      }
    }
  }

  @Test func anAnswerThatIsNotARefusalMayHaveBeenSentSoItIsInterrupted() async throws {
    let c = try await calls(FakeHTTPClient { request in
      request.url?.path == "/api/v1/health" ? healthy : HTTPResponse(statusCode: 502, body: Data("<html>bad gateway</html>".utf8))
    })

    await #expect(throws: ConnectionPathError.interrupted) { _ = try await c.execute(ServiceCommand(address: lampAddress, action: .on)) }
    await #expect(throws: ConnectionPathError.interrupted) { _ = try await c.devices() }
  }

  @Test func aBasePathIsKeptAheadOfTheAPIPath() async throws {
    for base in ["http://192.0.2.20:8080/insteon", "http://192.0.2.20:8080/insteon/"] {
      let http = FakeHTTPClient { request in request.url?.path.hasSuffix("/health") == true ? healthy : deviceList }
      let path = ServicePath(name: "lan", baseURL: URL(string: base)!, token: token, http: http)

      _ = try await path.open().devices()

      #expect(await http.lines == ["GET http://192.0.2.20:8080/insteon/api/v1/health", "GET http://192.0.2.20:8080/insteon/api/v1/devices"])
    }
  }

  @Test func aQueryAFragmentAndRepeatedSlashesOnTheBaseAreLeftOff() async throws {
    let http = FakeHTTPClient { _ in healthy }
    let path = ServicePath(name: "lan", baseURL: URL(string: "http://192.0.2.20:8080//insteon//sub/?token=x#frag")!, token: token, http: http)

    _ = try await path.open()

    #expect(await http.lines == ["GET http://192.0.2.20:8080/insteon/sub/api/v1/health"])
  }

  @Test func anAddressThatIsNotAnHTTPAddressIsNeverUsed() async {
    for text in ["ftp://192.0.2.20/", "mailto:someone", "http:///nohost"] {
      let http = FakeHTTPClient { _ in healthy }
      let path = ServicePath(name: "lan", baseURL: URL(string: text)!, token: token, http: http)

      await #expect(throws: ConnectionPathError.notReached("the service address isn't an HTTP address")) { _ = try await path.open() }
      #expect(await http.requests.isEmpty)
    }
  }

  @Test func aCauseThisLibraryCannotTypeIsKeptByNameNotInvented() async throws {
    for cause in ["hubErrorStatus", "somethingTheServiceAddsLater"] {
      let c = try await calls(FakeHTTPClient { request in
        request.url?.path == "/api/v1/health" ? healthy : refusal("modemUnavailable", sent: false, cause: cause, status: 503)
      })

      await #expect(throws: ConnectionError.modemUnavailable(cause: cause)) { _ = try await c.execute(ServiceCommand(address: lampAddress, action: .on)) }
    }
  }

  @Test func aListingThatCannotBeReadIsABadResponseAndOneBadEntryFailsTheWholeList() async throws {
    let bodies = ["not json", #"{"version":1,"devices":[{"address":"1A.2B.3C","productName":null,"canTurnOnAndOff":true,"canDim":true,"value":1,"lastAnsweredAt":null},{"address":"nonsense","productName":null,"canTurnOnAndOff":true,"canDim":true,"value":1,"lastAnsweredAt":null}]}"#]
    for body in bodies {
      let c = try await calls(FakeHTTPClient { request in request.url?.path == "/api/v1/health" ? healthy : json(body) })

      await #expect(throws: ConnectionPathError.badResponse) { _ = try await c.devices() }
    }
  }

  @Test func aReceiptThatCannotBeReadIsABadResponseNotALostPath() async throws {
    let c = try await calls(FakeHTTPClient { request in request.url?.path == "/api/v1/health" ? healthy : json("{}") })

    await #expect(throws: ConnectionPathError.badResponse) { _ = try await c.execute(ServiceCommand(address: lampAddress, action: .on)) }
  }

  @Test func aServicePathItselfRefusesPlainHTTPToAHostOutsideTheLocalNetwork() async {
    let http = FakeHTTPClient { _ in healthy }
    let path = ServicePath(name: "lan", baseURL: URL(string: "http://service.example.com")!, token: token, http: http)

    await #expect(throws: ConnectionPathError.notReached("the token is never sent over HTTP to a host outside the local network")) { _ = try await path.open() }
    #expect(await http.requests.isEmpty)
  }

  @Test func aNon5xxAnswerThatIsNotARefusalIsABadResponseFromSomethingThatIsNotTheService() async throws {
    for status in [400, 404, 302] {
      let c = try await calls(FakeHTTPClient { request in
        request.url?.path == "/api/v1/health" ? healthy : HTTPResponse(statusCode: status, body: Data("<html>no</html>".utf8))
      })

      await #expect(throws: ConnectionPathError.badResponse) { _ = try await c.execute(ServiceCommand(address: lampAddress, action: .on)) }
      await #expect(throws: ConnectionPathError.badResponse) { _ = try await c.devices() }
    }
  }

  @Test func aReceiptThatBreaksTheContractIsABadResponse() async throws {
    let status = #"{"group":1,"kind":"percent","value":128,"isOn":true,"percent":50,"label":null}"#
    let bodies = [
      #"{"version":1,"address":"1A.2B.3C","outcome":"acknowledged","status":null,"persistence":"someday"}"#,
      #"{"version":1,"address":"1A.2B.3C","outcome":"maybe","status":null,"persistence":"saved"}"#,
      #"{"version":1,"address":"1A.2B.3C","outcome":"read","status":{"group":1,"kind":"percent","value":128,"isOn":true,"percent":null,"label":null},"persistence":"saved"}"#,
      #"{"version":1,"address":"1A.2B.3C","outcome":"read","status":{"group":1,"kind":"named","value":128,"isOn":true,"percent":null,"label":null},"persistence":"saved"}"#,
      #"{"version":1,"address":"1A.2B.3C","outcome":"read","status":{"group":1,"kind":"mystery","value":128,"isOn":true,"percent":null,"label":null},"persistence":"saved"}"#,
      #"{"version":1,"address":"1A.2B.3C","outcome":"acknowledged","status":\#(status),"persistence":"saved"}"#
    ]
    for body in bodies {
      let c = try await calls(FakeHTTPClient { request in request.url?.path == "/api/v1/health" ? healthy : json(body) })

      await #expect(throws: ConnectionPathError.badResponse, "\(body)") { _ = try await c.execute(ServiceCommand(address: lampAddress, action: .on)) }
    }
  }
}

struct CancelingOpener: RouteOpening {
  let kind = "example-transport"
  func open(ticket: String?) async throws -> URL { throw CancellationError() }
}
