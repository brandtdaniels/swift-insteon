import Crypto
import Foundation
import InsteonCore

/// An authenticated website and versioned device API, independent of an HTTP server.
///
/// The HTTP adapter must bound request bodies before collecting them, and serve this over
/// an encrypted private connection or HTTPS. Browser authentication uses the fixed user
/// name `insteon`. The gateway keeps a digest of its expected Authorization header, not
/// the password. Its password is separate from the Hub's credentials.
public actor Gateway {
  private let controller: any GatewayControlling
  private nonisolated let authorizationDigest: [UInt8]
  private let formKey: String
  private var busy = false

  /// Creates a gateway with a password of at least 32 bytes and a per-process form key.
  /// Generate the password randomly and keep it out of command-line arguments and logs.
  public init(controller: any GatewayControlling, password: String, formKey: String = UUID().uuidString + UUID().uuidString) throws {
    guard (32...1024).contains(password.utf8.count), !password.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
      throw GatewayConfigurationError.weakPassword
    }
    guard !formKey.isEmpty else { throw GatewayConfigurationError.emptyFormKey }
    self.controller = controller
    let header = "Basic " + Data(("insteon:" + password).utf8).base64EncodedString()
    self.authorizationDigest = Array(SHA256.hash(data: Data(header.utf8)))
    self.formKey = formKey
  }

  /// Checks an Authorization header before an adapter reads a body or opens an event stream.
  /// Digests have fixed length and are compared without an early exit.
  public nonisolated func authorizes(_ header: String?) -> Bool {
    guard let header, header.utf8.count <= 4096 else { return false }
    return Self.matches(Array(SHA256.hash(data: Data(header.utf8))), authorizationDigest)
  }

  /// Handles a request. GET only reads cached descriptions; controls require explicit POSTs.
  /// Concurrent controller operations receive 409 rather than interleaving hardware work.
  public func respond(to request: GatewayRequest) async -> GatewayResponse {
    guard authorizes(request.headers["authorization"]) else {
      return Self.response(401, "Authentication required.", headers: ["WWW-Authenticate": "Basic realm=\"Insteon gateway\", charset=\"UTF-8\""])
    }
    guard request.body.count <= 8192 else { return Self.response(413, "Request body too large.") }
    do {
      if request.method == "GET", request.path == "/" || request.path == "/api/v1/devices" {
        guard !busy else { throw GatewayControlError.busy }
        busy = true
        defer { busy = false }
        let devices = try await controller.devices()
        if request.path == "/" {
          return Self.response(200, GatewayHTML.page(devices: devices, formKey: formKey), contentType: "text/html; charset=utf-8")
        }
        return try Self.json(GatewayDeviceList(devices: devices))
      }
      guard request.method == "POST" else { return Self.response(404, "Not found.") }
      let components = request.path.split(separator: "/", omittingEmptySubsequences: false)
      let mediaType = request.headers["content-type"]?.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).lowercased()
      let address: String
      let payload: CommandBody
      let isForm: Bool
      if components.count == 6, components[0].isEmpty, components[1] == "api", components[2] == "v1", components[3] == "devices", components[5] == "commands" {
        guard mediaType == "application/json" else { return Self.response(415, "Expected application/json.") }
        guard request.headers["x-insteon-request"] == "1" else { return Self.response(403, "An explicit API request is required.") }
        guard let object = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any], Set(object.keys).isSubset(of: ["action", "levelPercent"]) else {
          return Self.response(400, "Invalid command fields.")
        }
        address = String(components[4])
        payload = try JSONDecoder().decode(CommandBody.self, from: request.body)
        isForm = false
      } else if components.count == 3, components[0].isEmpty, components[1] == "devices" {
        guard mediaType == "application/x-www-form-urlencoded" else { return Self.response(415, "Expected a form.") }
        let fields = try Self.form(request.body)
        guard let supplied = fields["formKey"], Self.matches(Array(SHA256.hash(data: Data(supplied.utf8))), Array(SHA256.hash(data: Data(formKey.utf8)))) else {
          return Self.response(403, "The form expired. Reload the page and try again.")
        }
        guard Set(fields.keys).isSubset(of: ["action", "levelPercent", "formKey"]), let action = fields["action"].flatMap(GatewayCommand.Action.init(rawValue:)) else {
          return Self.response(400, "Invalid command fields.")
        }
        let level = fields["levelPercent"].flatMap { $0.isEmpty ? nil : $0 }
        guard level == nil || Int(level!) != nil else { return Self.response(400, "Invalid percentage.") }
        payload = CommandBody(action: action, levelPercent: level.flatMap(Int.init))
        address = String(components[2])
        isForm = true
      } else {
        return Self.response(404, "Not found.")
      }
      guard let parsed = InsteonAddress(address) else { return Self.response(400, "Invalid Insteon address.") }
      if let level = payload.levelPercent, payload.action != .on || !(0...100).contains(level) {
        return Self.response(400, "A percentage from 0 through 100 is accepted only with On.")
      }
      guard !busy else { throw GatewayControlError.busy }
      busy = true
      defer { busy = false }
      let result = try await controller.perform(GatewayCommand(address: parsed.description, action: payload.action, levelPercent: payload.levelPercent))
      if isForm { return Self.response(303, "Operation completed. Read status to verify a control's resulting state.", headers: ["Location": "/"]) }
      return try Self.json(result)
    } catch GatewayControlError.busy {
      return Self.response(409, "The gateway is busy. Try again explicitly; this request was not queued.")
    } catch GatewayControlError.unknownDevice {
      return Self.response(404, "Unknown device.")
    } catch GatewayControlError.invalidLevel {
      return Self.response(400, "The device or action does not accept that percentage.")
    } catch GatewayControlError.unsupportedControl {
      return Self.response(422, "The device does not support that control.")
    } catch is DecodingError {
      return Self.response(400, "Invalid command.")
    } catch is FormError {
      return Self.response(400, "Invalid form.")
    } catch is CancellationError {
      return Self.response(503, "Request canceled. Its hardware outcome may be unknown; read status before retrying.")
    } catch {
      return Self.response(502, "Operation failed. Its hardware outcome may be unknown; read status before retrying.")
    }
  }

  /// Common response headers, also used by streaming HTTP adapters.
  public nonisolated static var securityHeaders: [String: String] {
    ["Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer", "Content-Security-Policy": "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"]
  }

  private static func response(_ status: Int, _ text: String, contentType: String = "text/plain; charset=utf-8", headers: [String: String] = [:]) -> GatewayResponse {
    var all = securityHeaders.merging(headers, uniquingKeysWith: { _, value in value })
    all["Content-Type"] = contentType
    return GatewayResponse(status: status, headers: all, body: Data(text.utf8))
  }

  private static func json(_ value: some Encodable) throws -> GatewayResponse {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    var headers = securityHeaders
    headers["Content-Type"] = "application/json"
    return GatewayResponse(status: 200, headers: headers, body: data)
  }

  private nonisolated static func matches(_ left: [UInt8], _ right: [UInt8]) -> Bool {
    guard left.count == right.count else { return false }
    var difference: UInt8 = 0
    for index in left.indices { difference |= left[index] ^ right[index] }
    return difference == 0
  }

  private struct CommandBody: Decodable {
    let action: GatewayCommand.Action
    let levelPercent: Int?
  }

  private enum FormError: Error { case malformed }

  private static func form(_ body: Data) throws -> [String: String] {
    guard let text = String(data: body, encoding: .utf8) else { throw FormError.malformed }
    var fields: [String: String] = [:]
    for pair in text.split(separator: "&", omittingEmptySubsequences: false) {
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2,
            let key = String(parts[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
            let value = String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
            fields[key] == nil else { throw FormError.malformed }
      fields[key] = value
    }
    return fields
  }
}
