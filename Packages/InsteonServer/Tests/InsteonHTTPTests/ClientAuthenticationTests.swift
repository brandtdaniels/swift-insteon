import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import InsteonService
import Testing
@testable import InsteonHTTP

/// Per-client tokens and scopes, through the real router.
@Suite(.timeLimit(.minutes(1)))
struct ClientAuthenticationTests {
  let password = String(repeating: "p", count: 40)
  private let command = ByteBuffer(string: #"{"action":"off"}"#)

  private func fields(_ authorization: String?, command: Bool = false) -> HTTPFields {
    var fields: HTTPFields = [:]
    if let authorization { fields[.authorization] = authorization }
    if command {
      fields[.contentType] = "application/json"
      fields[HTTPField.Name("X-Insteon-Request")!] = "1"
    }
    return fields
  }

  private struct Setup {
    let service = FakeService()
    let clients = ClientStore(persistence: InMemoryClientPersistence())
    let capture = LogCapture()
    let app: Application<RouterResponder<BasicRequestContext>>
    init(password: String) throws {
      let service = service, clients = clients, capture = capture
      app = Application(responder: makeInsteonRouter(service: service, authentication: try HTTPAuthentication(password: password), clients: clients, logger: capture.logger).buildResponder())
    }
  }

  private func body(_ response: TestResponse) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
  }

  // MARK: Scopes

  @Test func aReadClientReadsAndFollowsEventsButCannotSendACommand() async throws {
    let setup = try Setup(password: password)
    let issued = try await setup.clients.issue(name: "Display", scope: .read)
    try await setup.app.test(.router) { client in
      for path in ["/api/v1/devices", "/api/v1/health", "/api/v1/openapi.json", "/api/v1/events"] {
        let response = try await client.execute(uri: path, method: .get, headers: fields("Bearer " + issued.token))
        #expect(response.status == .ok, "\(path)")
      }
      let refused = try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: fields("Bearer " + issued.token, command: true), body: command)
      #expect(refused.status == .forbidden)
      let json = try body(refused)
      #expect(json["code"] as? String == "forbidden")
      #expect(json["sent"] as? Bool == false)
      #expect(json["version"] as? Int == 1)
      #expect((json["message"] as? String)?.isEmpty == false)
    }
    #expect(await setup.service.commands.isEmpty)
  }

  @Test func aControlClientSendsACommand() async throws {
    let setup = try Setup(password: password)
    let issued = try await setup.clients.issue(name: "Phone", scope: .control)
    try await setup.app.test(.router) { client in
      let response = try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: fields("Bearer " + issued.token, command: true), body: command)
      #expect(response.status == .ok)
    }
    #expect(await setup.service.commands.count == 1)
  }

  @Test func theGatewayPasswordActsAsAdmin() async throws {
    let setup = try Setup(password: password)
    let basic = "Basic " + Data(("insteon:" + password).utf8).base64EncodedString()
    try await setup.app.test(.router) { client in
      let response = try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: fields(basic, command: true), body: command)
      #expect(response.status == .ok)
    }
  }

  @Test func theSchemeNameIsCaseInsensitive() async throws {
    let setup = try Setup(password: password)
    let issued = try await setup.clients.issue(name: "Phone", scope: .read)
    try await setup.app.test(.router) { client in
      for scheme in ["bearer", "BEARER", "Bearer"] {
        let response = try await client.execute(uri: "/api/v1/devices", method: .get, headers: fields(scheme + " " + issued.token))
        #expect(response.status == .ok, "\(scheme)")
      }
    }
  }

  // MARK: Refusing a credential

  @Test func aRevokedUnknownOrAlteredTokenIsRefusedBeforeAnyServiceAccess() async throws {
    let setup = try Setup(password: password)
    let revoked = try await setup.clients.issue(name: "Lost phone", scope: .admin)
    let live = try await setup.clients.issue(name: "Tablet", scope: .admin)
    try await setup.clients.revoke(id: revoked.client.id)
    let altered = String(live.token.dropLast()) + (live.token.hasSuffix("A") ? "B" : "A")
    try await setup.app.test(.router) { client in
      for token in [revoked.token, altered, "nonsense", ""] {
        let response = try await client.execute(uri: "/api/v1/devices", method: .get, headers: fields("Bearer " + token))
        #expect(response.status == .unauthorized)
        #expect(response.headers[.wwwAuthenticate] != nil)
        #expect(try body(response)["code"] as? String == "authenticationFailed")
      }
    }
    #expect(await setup.service.reads == 0)
  }

  @Test func aClientTokenIsNotAcceptedByTheBrowserRoutes() async throws {
    let setup = try Setup(password: password)
    let issued = try await setup.clients.issue(name: "Phone", scope: .admin)
    try await setup.app.test(.router) { client in
      for path in ["/", "/devices/1A.2B.3C", "/controls.js"] {
        let response = try await client.execute(uri: path, method: .get, headers: fields("Bearer " + issued.token))
        #expect(response.status == .unauthorized, "\(path)")
      }
    }
    #expect(await setup.service.reads == 0)
  }

  @Test func noTokenOrPasswordReachesTheLogOrAnError() async throws {
    let setup = try Setup(password: password)
    let issued = try await setup.clients.issue(name: "Display", scope: .read)
    let secret = try #require(issued.token.split(separator: ".").last.map(String.init))
    let texts: [String] = try await setup.app.test(.router) { client in
      var texts: [String] = []
      for header in ["Bearer " + issued.token, "Bearer " + issued.token + "x", "Basic " + Data(("insteon:" + password + "x").utf8).base64EncodedString()] {
        texts.append(String(buffer: try await client.execute(uri: "/api/v1/devices/1A.2B.3C/commands", method: .post, headers: fields(header, command: true), body: command).body))
      }
      return texts
    }
    let log = setup.capture.records.map(\.rendered).joined(separator: "\n")
    #expect(!setup.capture.records.isEmpty)
    for text in texts + [log] {
      #expect(!text.contains(secret))
      #expect(!text.contains(issued.token))
      #expect(!text.contains(password))
    }
    #expect(setup.capture.records.contains { $0.metadata["code"] == "forbidden" })
    #expect(setup.capture.records.contains { $0.metadata["code"] == "authenticationFailed" })
  }

  // MARK: The route table

  @Test func everyOperationDeclaresTheScopeItNeeds() {
    let expected: [APIOperation: ClientScope] = [.listDevices: .read, .health: .read, .streamEvents: .read, .openAPI: .read, .executeCommand: .control]
    for (operation, scope) in expected { #expect(operation.requiredScope == scope, "\(operation)") }
    for operation in APIOperation.allCases where !operation.isAPI { #expect(operation.requiredScope == .admin, "\(operation)") }
  }

  @Test func theDocumentShowsEachOperationsScopeAndTheBearerScheme() async throws {
    let document = OpenAPIDocument.document
    #expect(document["components"]?["securitySchemes"]?["bearerAuth"]?["scheme"] == "bearer")
    for operation in APIOperation.allCases {
      let described = try #require(document["paths"]?[operation.path]?[operation.method.rawValue.lowercased()])
      guard case let .array(security) = try #require(described["security"]) else { Issue.record("no security"); continue }
      let clientRequirement = security.first { $0["bearerAuth"] != nil }
      if operation.isAPI {
        #expect(clientRequirement?["bearerAuth"] == .array([.string(operation.requiredScope.rawValue)]), "\(operation)")
      } else {
        #expect(clientRequirement == nil, "\(operation) takes the gateway password only")
      }
      #expect(security.contains { $0["basicAuth"] != nil })
      #expect(described["x-required-scope"] == .string(operation.requiredScope.rawValue))
    }
  }

  @Test func anOperationAboveReadListsForbiddenAsAFailure() {
    for operation in APIOperation.allCases where operation.isAPI {
      #expect(operation.errorCodes.contains(.forbidden) == (operation.requiredScope > .read), "\(operation)")
    }
    #expect(APIErrorCode.forbidden.status == .forbidden)
    #expect(!APIErrorCode.forbidden.sent)
  }
}
