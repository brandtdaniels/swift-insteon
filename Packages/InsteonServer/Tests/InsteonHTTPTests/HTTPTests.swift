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
      for path in ["/", "/api/v1/devices", "/api/v1/events", "/unknown"] {
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

  @Test func aFailedEventWriterCancelsItsSourceSubscription() async throws {
    let (events, continuation) = AsyncStream<ServiceEvent>.makeStream()
    let (terminations, ended) = AsyncStream<AsyncStream<ServiceEvent>.Continuation.Termination>.makeStream()
    continuation.onTermination = { reason in ended.yield(reason); ended.finish() }
    continuation.yield(.statusChanged(address))
    let service = FakeService(eventStream: events)
    let response = await DeviceAPI(service: service).events()
    await #expect(throws: (any Error).self) {
      try await response.body.write(FailingEventWriter())
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
        #expect(response.status == .forbidden)
      }
      #expect(await service.commands.isEmpty)
      try await client.execute(uri: "/devices/1A.2B.3C", method: .post, headers: headers("application/x-www-form-urlencoded"), body: ByteBuffer(string: "action=off&formKey=" + key)) { response in
        #expect(response.status == .seeOther)
        #expect(response.headers[.location] == "/?notice=persistence-failed")
      }
      try await client.execute(uri: "/?notice=persistence-failed", method: .get, headers: headers()) { response in
        #expect(String(buffer: response.body).contains("snapshot could not be saved"))
      }
    }
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

  @Test(arguments: [ServiceControlError.busy, .unknownDevice, .invalidLevel, .unsupportedControl])
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
  struct Disconnected: Error {}
  mutating func write(_ buffer: ByteBuffer) async throws {
    if String(buffer: buffer).hasPrefix("data:") { throw Disconnected() }
  }
  consuming func finish(_ trailingHeaders: HTTPFields?) async throws {}
}

private actor FakeService: InsteonServiceAPI {
  var reads = 0
  var commands: [ServiceCommand] = []
  var subscriptions = 0
  let persistence: PersistenceOutcome
  let fails: Bool
  let refusal: ServiceControlError?
  let reading: DeviceStatus.Reading
  let eventStream: AsyncStream<ServiceEvent>?
  let address = InsteonAddress(0x1A, 0x2B, 0x3C)
  init(persistence: PersistenceOutcome = .saved, fails: Bool = false, refusal: ServiceControlError? = nil, reading: DeviceStatus.Reading = .percent(50), eventStream: AsyncStream<ServiceEvent>? = nil) {
    self.persistence = persistence; self.fails = fails; self.refusal = refusal; self.reading = reading
    self.eventStream = eventStream
  }
  func devices() async throws -> [ServiceDevice] {
    reads += 1
    return [ServiceDevice(address: address, productName: "<script>Example</script>", canTurnOnAndOff: true, canDim: true, value: 128, lastAnsweredAt: nil)]
  }
  func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    commands.append(command)
    if let refusal { throw refusal }
    if fails { throw Diagnostic() }
    let isOn: Bool
    if case let .onOff(value) = reading { isOn = value } else { isOn = true }
    let status = command.action == .status ? DeviceStatus(group: 1, value: 128, allLinkDatabaseDelta: 0, reading: reading, isOn: isOn) : nil
    return CommandReceipt(address: address, outcome: command.action == .on || command.action == .off ? .acknowledged : .read, status: status, persistence: persistence)
  }
  func events() async -> AsyncStream<ServiceEvent> {
    subscriptions += 1
    if let eventStream { return eventStream }
    let address = self.address
    return AsyncStream { continuation in
      continuation.yield(.statusChanged(address))
      continuation.finish()
    }
  }
  struct Diagnostic: Error, CustomStringConvertible { var description: String { "private diagnostic" } }
}
