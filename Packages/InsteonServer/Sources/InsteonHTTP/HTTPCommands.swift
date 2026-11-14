import Foundation
import Hummingbird
import HTTPTypes
import InsteonCore
import InsteonService

enum HTTPInputError: Error { case invalid, unsupportedMedia, missingAPIMarker, invalidFormKey }

enum HTTPBody {
  static let limit = 8192
  static func read(_ request: Request) async throws -> Data {
    Data(try await request.body.collect(upTo: limit).readableBytesView)
  }
  static func mediaType(_ request: Request) -> String? {
    request.headers[.contentType]?.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).lowercased()
  }
}

/// Input decoding belongs to HTTP; domain validation remains in the service.
struct HTTPCommand: Decodable {
  enum Action: String, Decodable { case identify, status, on, off }
  let action: Action
  let levelPercent: Int?

  func serviceCommand(address: String?) throws -> ServiceCommand {
    guard let address, let address = InsteonAddress(address) else { throw HTTPInputError.invalid }
    let operation: ServiceCommand.Action
    switch action {
    case .identify: operation = .identify
    case .status: operation = .status
    case .on: operation = .on
    case .off: operation = .off
    }
    return ServiceCommand(address: address, action: operation, levelPercent: levelPercent)
  }

  static func json(_ request: Request) async throws -> HTTPCommand {
    guard HTTPBody.mediaType(request) == "application/json" else { throw HTTPInputError.unsupportedMedia }
    guard request.headers[HTTPField.Name("X-Insteon-Request")!] == "1" else { throw HTTPInputError.missingAPIMarker }
    let data = try await HTTPBody.read(request)
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], Set(object.keys).isSubset(of: ["action", "levelPercent"]) else { throw HTTPInputError.invalid }
    return try JSONDecoder().decode(Self.self, from: data)
  }
}

/// Browser form parsing and cross-origin request protection, separate from authentication.
struct BrowserFormProtection: Sendable {
  let key = UUID().uuidString + UUID().uuidString

  func command(_ request: Request) async throws -> HTTPCommand {
    guard HTTPBody.mediaType(request) == "application/x-www-form-urlencoded" else { throw HTTPInputError.unsupportedMedia }
    let data = try await HTTPBody.read(request)
    guard let text = String(data: data, encoding: .utf8) else { throw HTTPInputError.invalid }
    var fields: [String: String] = [:]
    for pair in text.split(separator: "&", omittingEmptySubsequences: false) {
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2,
            let name = String(parts[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
            let value = String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
            fields[name] == nil else { throw HTTPInputError.invalid }
      fields[name] = value
    }
    guard let supplied = fields["formKey"], SecureDigest.matches(SecureDigest.of(supplied), SecureDigest.of(key)) else { throw HTTPInputError.invalidFormKey }
    guard Set(fields.keys).isSubset(of: ["action", "levelPercent", "formKey"]), let action = fields["action"].flatMap(HTTPCommand.Action.init(rawValue:)) else { throw HTTPInputError.invalid }
    let levelText = fields["levelPercent"].flatMap { $0.isEmpty ? nil : $0 }
    let level = levelText.flatMap(Int.init)
    guard levelText == nil || level != nil else { throw HTTPInputError.invalid }
    return HTTPCommand(action: action, levelPercent: level)
  }
}
