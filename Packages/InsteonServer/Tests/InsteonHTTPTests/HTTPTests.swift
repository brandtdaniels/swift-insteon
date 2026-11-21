import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonCore
import InsteonService
import ServiceLifecycleTestKit
import Testing
@testable import InsteonHTTP

@Suite(.timeLimit(.minutes(1)))
struct HTTPTests {
  let password = String(repeating: "p", count: 40)
  let address = InsteonAddress(0x1A, 0x2B, 0x3C)

  private var authorization: String { "Basic " + Data(("insteon:" + password).utf8).base64EncodedString() }
  private func headers(_ type: String? = nil, marker: Bool = false) -> HTTPFields {
    var fields: HTTPFields = [.authorization: authorization]
    fields[.contentType] = type
    if marker { fields[HTTPField.Name("X-Insteon-Request")!] = "1" }
    return fields
  }

  @Test(arguments: [TestingSetup.router, .live])
  func authenticationProtectsAllRoutesBeforeServiceAccess(_ setup: TestingSetup) async throws {
    let service = FakeService()
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(setup) { client in
      for path in ["/", "/api/v1/devices", "/api/v1/events", "/devices/1A.2B.3C", "/unknown"] {
        try await client.execute(uri: path, method: .get) { response in
          #expect(response.status == .unauthorized)
          #expect(response.headers[.wwwAuthenticate] != nil)
          #expect(response.headers[.cacheControl] == "no-store")
        }
      }
      #expect(await service.reads == 0)
      #expect(await service.commands.isEmpty)
      #expect(await service.subscriptions == 0)
      try await client.execute(uri: "/api/v1/devices", method: .get, headers: [.authorization: "Basic incorrect"]) { response in
        #expect(response.status == .unauthorized)
      }
      try await client.execute(uri: "/api/v1/devices", method: .get, headers: headers()) { response in
        #expect(response.status == .ok)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
        #expect(object["version"] as? Int == 1)
      }
    }
  }

  @Test func liveCardReadsUseCachedStateWithoutExecutingCommands() async throws {
    let service = FakeService()
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      let response = try await client.execute(uri: "/devices/1A.2B.3C", method: .get, headers: headers())
      #expect(response.status == .ok)
      #expect(response.headers[.contentType] == "text/html; charset=utf-8")
      #expect(response.headers[.cacheControl] == "no-store")
      let html = String(buffer: response.body)
      #expect(html.hasPrefix("<article "))
      #expect(html.contains("Cached: 50%"))
      #expect(!html.contains("<!doctype"))
      await service.setQueriesBusy(true)
      let busy = try await client.execute(uri: "/devices/1A.2B.3C", method: .get, headers: headers())
      #expect(busy.status == .conflict)
      await service.setQueriesBusy(false)
      let missing = try await client.execute(uri: "/devices/1A.2B.04", method: .get, headers: headers())
      #expect(missing.status == .notFound)
      let invalid = try await client.execute(uri: "/devices/invalid", method: .get, headers: headers())
      #expect(invalid.status == .badRequest)
    }
    #expect(await service.commands.isEmpty)
  }

  @Test func theSameServiceSuppliesCommandsAndEventsWithoutAConcreteBackend() async throws {
    let service = FakeService()
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: headers("application/json", marker: true), body: ByteBuffer(string: #"{"action":"on","levelPercent":50}"#)) { response in
        #expect(response.status == .ok)
      }
      try await client.execute(uri: "/api/v1/events", method: .get, headers: headers()) { response in
        #expect(response.status == .ok)
        #expect(response.headers[.contentType] == "text/event-stream")
        #expect(String(buffer: response.body).contains("\"kind\":\"statusChanged\""))
        #expect(String(buffer: response.body).contains("1A.2B.3C"))
      }
    }
    #expect(await service.commands == [ServiceCommand(address: address, action: .on, levelPercent: 50)])
    #expect(await service.subscriptions == 1)
  }

  @Test(arguments: [ServiceCommand.Action.on, .status])
  func softwareCompletionEventsPreserveReceiptsAndStructuredReadings(_ action: ServiceCommand.Action) async throws {
    let command = ServiceCommand(address: address, action: action)
    let reading = action == .status ? DeviceStatus(group: 1, value: 128, allLinkDatabaseDelta: 0, reading: .percent(50), isOn: true) : nil
    let receipt = CommandReceipt(address: address, outcome: action == .status ? .read : .acknowledged, status: reading, persistence: .failed)
    let events = AsyncStream<ServiceEvent> { continuation in
      continuation.yield(.commandCompleted(command, receipt))
      continuation.finish()
    }
    let service = FakeService(eventStream: events)
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      let response = try await client.execute(uri: "/api/v1/events", method: .get, headers: headers())
      let line = try #require(String(buffer: response.body).split(separator: "\n").first { $0.hasPrefix("data: ") })
      let event = try #require(try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any])
      #expect(event["kind"] as? String == "commandCompleted")
      #expect(event["address"] as? String == address.description)
      let completion = try #require(event["completion"] as? [String: Any])
      #expect(completion["action"] as? String == (action == .status ? "status" : "on"))
      let result = try #require(completion["result"] as? [String: Any])
      #expect(result["persistence"] as? String == "failed")
      #expect(result["outcome"] as? String == (action == .status ? "read" : "acknowledged"))
      if action == .status {
        #expect((result["status"] as? [String: Any])?["percent"] as? Int == 50)
      } else {
        #expect(result["status"] == nil)
      }
    }
  }

  @Test(arguments: [true, false])
  func gracefulShutdownFinishesAnOpenEventResponse(_ shutdownBeforeRequest: Bool) async throws {
    let (source, continuation) = AsyncStream<ServiceEvent>.makeStream()
    defer { continuation.finish() }
    try await testGracefulShutdown { trigger in
      let events = AsyncStream<ServiceEvent>(unfolding: {
        if !shutdownBeforeRequest { trigger.triggerGracefulShutdown() }
        return await source.first { _ in true }
      })
      let service = FakeService(eventStream: events)
      let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
      // A source that never ends must not keep the HTTP host alive after shutdown.
      if shutdownBeforeRequest { trigger.triggerGracefulShutdown() }
      try await app.test(.router) { client in
        try await client.execute(uri: "/api/v1/events", method: .get, headers: headers()) { response in
          #expect(response.status == .ok)
          #expect(String(buffer: response.body).contains(": connected"))
        }
      }
      #expect(await service.subscriptions == 1)
    }
  }

  @Test func anUnwrittenEventResponseDoesNotCreateASubscription() async {
    let service = FakeService()
    let response = await DeviceAPI(service: service).events()
    #expect(response.status == .ok)
    #expect(await service.subscriptions == 0)
  }

  @Test(arguments: [false, true])
  func aFailedEventWriterCancelsItsSourceSubscription(_ failOnGreeting: Bool) async throws {
    let (events, continuation) = AsyncStream<ServiceEvent>.makeStream()
    let (terminations, ended) = AsyncStream<AsyncStream<ServiceEvent>.Continuation.Termination>.makeStream()
    continuation.onTermination = { reason in ended.yield(reason); ended.finish() }
    continuation.yield(.statusChanged(address))
    let service = FakeService(eventStream: events)
    let response = await DeviceAPI(service: service).events()
    await #expect(throws: (any Error).self) {
      try await response.body.write(FailingEventWriter(failOnGreeting: failOnGreeting))
    }
    let termination = await terminations.first { _ in true }
    guard case .cancelled? = termination else {
      Issue.record("A disconnected event writer must cancel its source")
      return
    }
  }

  @Test func statusRemainsStructuredAndPersistenceFailureDoesNotBecomeHTTPFailure() async throws {
    let service = FakeService(persistence: .failed)
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      for action in ["on", "status"] {
        let body = "{\"action\":\"" + action + "\"}"
        try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: headers("application/json", marker: true), body: ByteBuffer(string: body)) { response in
          #expect(response.status == .ok)
          let object = try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
          #expect(object["persistence"] as? String == "failed")
          #expect(object["outcome"] as? String == (action == "on" ? "acknowledged" : "read"))
          if action == "status" {
            let status = try #require(object["status"] as? [String: Any])
            #expect(status["kind"] as? String == "percent")
            #expect(status["percent"] as? Int == 50)
            #expect(status["value"] as? Int == 128)
          }
        }
      }
    }
  }

  @Test func HTMLIsEscapedAndFormsRequireTheirKey() async throws {
    let service = FakeService(persistence: .failed)
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      let page = try await client.execute(uri: "/", method: .get, headers: headers())
      let text = String(buffer: page.body)
      #expect(text.contains("&lt;script&gt;Example&lt;/script&gt;"))
      #expect(!text.contains("<script>"))
      #expect(text.contains("Cached"))
      let start = try #require(text.range(of: "name=\"formKey\" value=\""))
      let key = try #require(text[start.upperBound...].split(separator: "\"").first)
      try await client.execute(uri: "/devices/1A.2B.3C", method: .post, headers: headers("application/x-www-form-urlencoded"), body: ByteBuffer(string: "action=off")) { response in
        #expect(response.status == .seeOther)
      }
      #expect(await service.commands.isEmpty)
      try await client.execute(uri: "/devices/1A.2B.3C", method: .post, headers: headers("application/x-www-form-urlencoded"), body: ByteBuffer(string: "action=off&formKey=" + key)) { response in
        #expect(response.status == .seeOther)
        #expect(response.headers[.location] == "/?notice=persistence-failed&device=1A.2B.3C#device-1A.2B.3C")
      }
      try await client.execute(uri: "/?notice=persistence-failed", method: .get, headers: headers()) { response in
        #expect(String(buffer: response.body).contains("snapshot could not be saved"))
      }
    }
  }

  @Test(arguments: ["on", "off", "status", "identify"], [false, true])
  func fragmentCommandsReturnOnlyTheAffectedCard(_ action: String, _ fails: Bool) async throws {
    let service = FakeService(fails: fails)
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      let page = try await client.execute(uri: "/", method: .get, headers: headers())
      let text = String(buffer: page.body)
      #expect(text.contains("src=\"/controls.js\""))
      let start = try #require(text.range(of: "name=\"formKey\" value=\""))
      let key = try #require(text[start.upperBound...].split(separator: "\"").first)
      var fields = headers("application/x-www-form-urlencoded")
      fields[HTTPField.Name("X-Insteon-Fragment")!] = "device"
      let response = try await client.execute(uri: "/devices/1A.2B.3C", method: .post, headers: fields, body: ByteBuffer(string: "action=" + action + "&formKey=" + key))
      let html = String(buffer: response.body)
      #expect(response.status == (fails ? (action == "on" || action == "off" ? .badGateway : .gatewayTimeout) : .ok))
      #expect(response.headers[.location] == nil)
      #expect(response.headers[.contentType] == "text/html; charset=utf-8")
      #expect(html.hasPrefix("<article "))
      #expect(html.contains("id=\"device-1A.2B.3C\""))
      #expect(!html.contains("<!doctype"))
      #expect(!html.contains("private diagnostic"))
      #expect(html.contains("role=\"alert\"") == fails)
    }
    #expect(await service.commands.count == 1)
  }

  @Test(arguments: ["busy", "expired", "storage"])
  func fragmentsKeepRecoverableFailuresAndStorageWarningsOnTheCard(_ mode: String) async throws {
    let service = FakeService(persistence: mode == "storage" ? .failed : .saved, refusal: mode == "busy" ? .busy : nil)
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      let page = try await client.execute(uri: "/", method: .get, headers: headers())
      let text = String(buffer: page.body)
      let start = try #require(text.range(of: "name=\"formKey\" value=\""))
      let key = try #require(text[start.upperBound...].split(separator: "\"").first)
      if mode == "busy" { await service.setQueriesBusy(true) }
      var fields = headers("application/x-www-form-urlencoded")
      fields[HTTPField.Name("X-Insteon-Fragment")!] = "device"
      let suppliedKey = mode == "expired" ? "expired" : String(key)
      let response = try await client.execute(uri: "/devices/1A.2B.3C", method: .post, headers: fields, body: ByteBuffer(string: "action=on&formKey=" + suppliedKey))
      let html = String(buffer: response.body)
      #expect(html.hasPrefix("<article "))
      #expect(html.contains("Read status</button>"))
      #expect(html.contains("value=\"" + key + "\""))
      switch mode {
      case "busy":
        #expect(response.status == .conflict)
        #expect(html.contains("The service is busy"))
        #expect(html.contains("previously displayed"))
      case "expired":
        #expect(response.status == .forbidden)
        #expect(html.contains("No command was sent"))
      default:
        #expect(response.status == .ok)
        #expect(html.contains("snapshot could not be saved"))
      }
    }
    #expect(await service.commands.count == (mode == "expired" ? 0 : 1))
  }

  @Test func browserHelperIsAuthenticatedAndAllowedByTheSecurityPolicy() async throws {
    let service = FakeService()
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      let denied = try await client.execute(uri: "/controls.js", method: .get)
      #expect(denied.status == .unauthorized)
      let script = try await client.execute(uri: "/controls.js", method: .get, headers: headers())
      #expect(script.status == .ok)
      #expect(script.headers[.contentType] == "text/javascript; charset=utf-8")
      let page = try await client.execute(uri: "/", method: .get, headers: headers())
      let policy = try #require(page.headers[HTTPField.Name("Content-Security-Policy")!])
      #expect(policy.contains("script-src 'self'"))
      #expect(policy.contains("connect-src 'self'"))
      #expect(!policy.contains("script-src 'unsafe-inline'"))
    }
    #expect(await service.commands.isEmpty)
  }

  @Test func browserHelperReconnectsThroughTheTestedLinkInsteadOfKeepingAClosedStream() async throws {
    let service = FakeService()
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      let response = try await client.execute(uri: "/controls.js", method: .get, headers: headers())
      let script = String(buffer: response.body)
      #expect(script.contains(LiveLink.source))
      #expect(script.components(separatedBy: "new EventSource(").count == 2)
      // A first connection refreshes; a resumed one refreshes only when the server reports a gap.
      #expect(script.contains("onOpen: resumed => { if (!resumed) synchronize(); }"))
      #expect(script.contains("update.kind === 'gap'"))
      #expect(script.contains("?lastEventId="))
      #expect(!script.contains("if (events ||"))
    }
  }

  @Test(arguments: ["action=off", "action=off&formKey=expired", "action=on&levelPercent=invalid&formKey=VALID", "action=off&action=on&formKey=VALID"])
  func invalidBrowserFormsReturnToThePageWithoutSendingCommands(_ form: String) async throws {
    let service = FakeService()
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      let page = try await client.execute(uri: "/", method: .get, headers: headers())
      let text = String(buffer: page.body)
      let start = try #require(text.range(of: "name=\"formKey\" value=\""))
      let key = try #require(text[start.upperBound...].split(separator: "\"").first)
      let response = try await client.execute(uri: "/devices/1A.2B.3C", method: .post, headers: headers("application/x-www-form-urlencoded"), body: ByteBuffer(string: form.replacingOccurrences(of: "VALID", with: String(key))))
      #expect(response.status == .seeOther)
      let location = try #require(response.headers[.location])
      let path = String(location.split(separator: "#")[0])
      let recovered = try await client.execute(uri: path, method: .get, headers: headers())
      #expect(recovered.status == .ok)
      #expect(String(buffer: recovered.body).contains("role=\"alert\""))
      #expect(String(buffer: recovered.body).contains("Read status</button>"))
    }
    #expect(await service.commands.isEmpty)
  }

  @Test(arguments: [false, true], ["status", "on"])
  func browserCommandFailuresReturnToTheDeviceCardWithoutRepeatingTheCommand(_ busy: Bool, _ action: String) async throws {
    let service = FakeService(fails: !busy, refusal: busy ? .busy : nil)
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      let page = try await client.execute(uri: "/", method: .get, headers: headers())
      let text = String(buffer: page.body)
      let start = try #require(text.range(of: "name=\"formKey\" value=\""))
      let key = try #require(text[start.upperBound...].split(separator: "\"").first)
      if busy { await service.setQueriesBusy(true) }
      let response = try await client.execute(uri: "/devices/1A.2B.3C", method: .post, headers: headers("application/x-www-form-urlencoded"), body: ByteBuffer(string: "action=" + action + "&formKey=" + key))
      #expect(response.status == .seeOther)
      let location = try #require(response.headers[.location])
      #expect(location.hasPrefix("/?"))
      #expect(location.hasSuffix("#device-1A.2B.3C"))
      let path = String(location.split(separator: "#")[0])
      for _ in 0..<2 {
        let updated = try await client.execute(uri: path, method: .get, headers: headers())
        let html = String(buffer: updated.body)
        #expect(updated.status == .ok)
        #expect(updated.headers[.contentType] == "text/html; charset=utf-8")
        #expect(html.contains("role=\"alert\""))
        #expect(html.contains(busy ? "The service is busy" : action == "status" ? "Could not read status" : "hardware outcome may be unknown"))
        #expect(html.contains("id=\"device-1A.2B.3C\""))
        #expect(html.contains("Read status</button>"))
        #expect(!html.contains("private diagnostic"))
      }
    }
    #expect(await service.commands.count == 1)
  }

  @Test(arguments: ["{", #"{"action":"remove"}"#, #"{"action":"on","levelPercent":"50"}"#, #"{"action":"on","levle":50}"#])
  func malformedCommandsNeverReachTheService(_ json: String) async throws {
    let service = FakeService()
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: headers("application/json", marker: true), body: ByteBuffer(string: json)) { response in
        #expect(response.status == .badRequest)
      }
    }
    #expect(await service.commands.isEmpty)
  }

  @Test func APIsRequireExplicitJSONAndBoundBodies() async throws {
    let service = FakeService()
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      let path = "/api/v1/devices/1A.2B.3C/commands"
      try await client.execute(uri: path, method: .post, headers: headers(), body: ByteBuffer(string: #"{"action":"on"}"#)) { response in
        #expect(response.status == .unsupportedMediaType)
      }
      try await client.execute(uri: path, method: .post, headers: headers("application/json"), body: ByteBuffer(string: #"{"action":"on"}"#)) { response in
        #expect(response.status == .forbidden)
      }
      try await client.execute(uri: path, method: .post, headers: headers("application/json", marker: true), body: ByteBuffer(repeating: 32, count: 8193)) { response in
        #expect(response.status == .contentTooLarge)
      }
    }
    #expect(await service.commands.isEmpty)
  }

  @Test func executionErrorsAreRedactedAndNotRetried() async throws {
    let service = FakeService(fails: true)
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: headers("application/json", marker: true), body: ByteBuffer(string: #"{"action":"off"}"#)) { response in
        #expect(response.status == .badGateway)
        #expect(!String(buffer: response.body).contains("private diagnostic"))
      }
    }
    #expect(await service.commands.count == 1)
  }

  @Test func credentialsCanBeValidatedWithoutAnyServiceOrController() {
    #expect(throws: HTTPAuthenticationError.self) { try HTTPAuthentication(password: "short") }
  }

  @Test(arguments: ["Basic ", "basic ", "BASIC ", "bAsIc   "])
  func basicAuthenticationAcceptsTheHTTPAuthSchemeGrammar(_ prefix: String) async throws {
    let service = FakeService()
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    let credential = Data(("insteon:" + password).utf8).base64EncodedString()
    try await app.test(.router) { client in
      try await client.execute(uri: "/api/v1/devices", method: .get, headers: [.authorization: prefix + credential]) { response in
        #expect(response.status == .ok)
      }
    }
    #expect(await service.reads == 1)
  }

  @Test func basicAuthenticationStillRejectsWrongCredentialsAndMalformedHeaders() throws {
    let authentication = try HTTPAuthentication(password: password)
    let credential = Data(("insteon:" + password).utf8).base64EncodedString()
    for header in ["Bearer " + credential, "Basic", "Basic wrong", "Basic " + credential + " extra", "Basic\t" + credential] {
      #expect(!authentication.authorizes(header))
    }
    #expect(!authentication.authorizes(nil))
  }

  @Test func authenticationPolicyCanBeReplacedWithoutChangingTheServiceOrRoutes() async throws {
    let service = FakeService()
    let app = Application(responder: makeInsteonRouter(service: service, authentication: AlternateAuthentication()).buildResponder())
    try await app.test(.router) { client in
      try await client.execute(uri: "/api/v1/devices", method: .get) { response in
        #expect(response.status == .unauthorized)
        #expect(response.headers[.wwwAuthenticate] == "Test")
      }
      try await client.execute(uri: "/api/v1/devices", method: .get, headers: [.authorization: "Test accepted"]) { response in
        #expect(response.status == .ok)
      }
    }
    #expect(await service.reads == 1)
  }

  @Test(arguments: [ServiceControlError.busy, .unknownDevice, .invalidLevel, .unsupportedControl, .notIdentified, .notLinked, .modemUnavailable(.hubUnreachable)])
  func serviceRefusalsHaveAnHTTPMapping(_ failure: ServiceControlError) async throws {
    let service = FakeService(refusal: failure)
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: headers("application/json", marker: true), body: ByteBuffer(string: #"{"action":"off"}"#)) { response in
        switch failure {
        case .busy: #expect(response.status == .conflict)
        case .unknownDevice: #expect(response.status == .notFound)
        case .invalidLevel: #expect(response.status == .badRequest)
        case .unsupportedControl: #expect(response.status == .unprocessableContent)
        case .notIdentified, .notLinked: #expect(response.status == .conflict)
        case .modemUnavailable: #expect(response.status == .serviceUnavailable)
        }
      }
    }
    #expect(await service.commands.count == 1)
  }

  @Test(arguments: [DeviceStatus.Reading.onOff(false), .named("Quiet"), .raw])
  func statusVariantsRemainMachineReadable(_ reading: DeviceStatus.Reading) async throws {
    let service = FakeService(reading: reading)
    let app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password)).buildResponder())
    try await app.test(.router) { client in
      try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: headers("application/json", marker: true), body: ByteBuffer(string: #"{"action":"status"}"#)) { response in
        let object = try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
        let status = try #require(object["status"] as? [String: Any])
        #expect(status["value"] as? Int == 128)
        switch reading {
        case .onOff:
          #expect(status["kind"] as? String == "onOff")
          #expect(status["isOn"] as? Bool == false)
        case .named:
          #expect(status["kind"] as? String == "named")
          #expect(status["label"] as? String == "Quiet")
        case .raw: #expect(status["kind"] as? String == "raw")
        case .percent: Issue.record("Unexpected reading in this test")
        }
      }
    }
  }
}

private struct AlternateAuthentication: HTTPAuthenticating {
  var challenge: String { "Test" }
  func authorizes(_ header: String?) -> Bool { header == "Test accepted" }
}

private struct FailingEventWriter: ResponseBodyWriter {
  var failOnGreeting = false
  struct Disconnected: Error {}
  mutating func write(_ buffer: ByteBuffer) async throws {
    if failOnGreeting || String(buffer: buffer).hasPrefix("id:") { throw Disconnected() }
  }
  consuming func finish(_ trailingHeaders: HTTPFields?) async throws {}
}

actor FakeService: InsteonServiceAPI {
  private var queriesBusy = false
  var reads = 0
  var commands: [ServiceCommand] = []
  var subscriptions = 0
  let persistence: PersistenceOutcome
  let fails: Bool
  let refusal: ServiceControlError?
  let failure: (any Error)?
  let reading: DeviceStatus.Reading
  let eventStream: AsyncStream<ServiceEvent>?
  /// Each subscription gets its own stream that never ends; the actor keeps its continuation open.
  let endlessEvents: Bool
  /// Items a sequenced subscription starts with, such as a gap.
  let scriptedItems: [SequencedItem]
  /// The notification rules the service holds, and the refusal every rule call answers with.
  private(set) var rules: [ServiceNotificationRule] = []
  let ruleFailure: NotificationRuleError?
  /// The cursor of each sequenced subscription.
  private(set) var cursors: [EventCursor?] = []
  private var openSources: [AsyncStream<ServiceEvent>.Continuation] = []
  var reported = ServiceHealth(readiness: .ready, modem: .connected, lastHardwareExchange: nil, deviceInformationUpdated: nil, persistence: .saved, checkedAt: Date(timeIntervalSince1970: 1_800_000_000))
  let address = InsteonAddress(0x1A, 0x2B, 0x3C)
  init(persistence: PersistenceOutcome = .saved, fails: Bool = false, refusal: ServiceControlError? = nil, failure: (any Error)? = nil, reading: DeviceStatus.Reading = .percent(50), eventStream: AsyncStream<ServiceEvent>? = nil, endlessEvents: Bool = false, scriptedItems: [SequencedItem] = [], ruleFailure: NotificationRuleError? = nil) {
    self.ruleFailure = ruleFailure
    self.endlessEvents = endlessEvents
    self.scriptedItems = scriptedItems
    self.persistence = persistence; self.fails = fails; self.refusal = refusal; self.failure = failure; self.reading = reading
    self.eventStream = eventStream
  }
  func devices() async throws -> [ServiceDevice] {
    reads += 1
    if queriesBusy { throw ServiceControlError.busy }
    return [ServiceDevice(address: address, productName: "<script>Example</script>", canTurnOnAndOff: true, canDim: true, value: 128, lastAnsweredAt: nil)]
  }
  func notificationRules() async throws -> [ServiceNotificationRule] {
    if let ruleFailure { throw ruleFailure }
    return rules
  }
  func putNotificationRule(_ rule: ServiceNotificationRule) async throws {
    if let ruleFailure { throw ruleFailure }
    if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index] = rule } else { rules.append(rule) }
  }
  func removeNotificationRule(id: String) async throws {
    if let ruleFailure { throw ruleFailure }
    guard rules.contains(where: { $0.id == id }) else { throw NotificationRuleError.unknownRule }
    rules.removeAll { $0.id == id }
  }
  /// What the service says its backup holds, and how many times it was asked.
  private(set) var backups = 0
  func homeBackup() async -> HomeBackup {
    backups += 1
    let lamp = BackupDevice(address: address, type: "Example", identity: BackupIdentity(category: 0x01, subcategory: 0x02, firmwareVersion: 0x41), engine: .i2, allLinkDatabase: BackupDatabase(delta: 0x07, records: [
      BackupRecord(state: .inUse, role: .responder, group: 1, address: InsteonAddress(0x11, 0x22, 0x33), data: [0xFF, 0x1F, 0x01], memoryAddress: 0x0FFF),
      BackupRecord(state: .end, role: .responder, group: 0, address: InsteonAddress(0, 0, 0), data: [0, 0, 0], memoryAddress: 0x0FF7)
    ]))
    let sensor = BackupDevice(address: InsteonAddress(0x0A, 0x0B, 0x0C), unreadable: BackupUnreadable(reason: .notCached))
    return HomeBackup(createdAt: Date(timeIntervalSince1970: 1_800_000_000), source: .service, modem: BackupModem(address: InsteonAddress(0x11, 0x22, 0x33), allLinkDatabase: [BackupRecord(state: .inUse, role: .controller, group: 1, address: address, data: [1, 2, 3])]), devices: [lamp, sensor])
  }
  func setQueriesBusy(_ busy: Bool) { queriesBusy = busy }
  func setHealth(_ health: ServiceHealth) { reported = health }
  func health() async -> ServiceHealth { reported }
  func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    commands.append(command)
    if let refusal { throw refusal }
    if let failure { throw failure }
    if fails { throw Diagnostic() }
    let isOn: Bool
    if case let .onOff(value) = reading { isOn = value } else { isOn = true }
    let status = command.action == .status ? DeviceStatus(group: 1, value: 128, allLinkDatabaseDelta: 0, reading: reading, isOn: isOn) : nil
    return CommandReceipt(address: address, outcome: command.action == .on || command.action == .off ? .acknowledged : .read, status: status, persistence: persistence)
  }
  /// Numbers this service's events 1, 2, 3 in the run named `fake`.
  func sequencedEvents(after cursor: EventCursor?) async -> SequencedEvents {
    cursors.append(cursor)
    let source = await events()
    let (stream, continuation) = AsyncThrowingStream<SequencedItem, any Error>.makeStream()
    for item in scriptedItems { continuation.yield(item) }
    let task = Task {
      var number: UInt64 = 0
      for await event in source {
        number += 1
        continuation.yield(.event(event, EventCursor(runID: "fake", sequence: number)))
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
    return SequencedEvents(stream)
  }
  func events() async -> AsyncStream<ServiceEvent> {
    subscriptions += 1
    if endlessEvents {
      let (stream, continuation) = AsyncStream<ServiceEvent>.makeStream()
      openSources.append(continuation)
      return stream
    }
    if let eventStream { return eventStream }
    let address = self.address
    return AsyncStream { continuation in
      continuation.yield(.statusChanged(address))
      continuation.finish()
    }
  }
  struct Diagnostic: Error, CustomStringConvertible { var description: String { "private diagnostic" } }
}
