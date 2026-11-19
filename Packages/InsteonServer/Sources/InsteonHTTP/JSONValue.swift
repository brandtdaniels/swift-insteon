import Foundation

/// A JSON value built in Swift, so the API description is data the compiler checks and encodes the
/// same way every time: objects are written with sorted keys.
enum JSONValue: Equatable, Sendable {
  case null
  case bool(Bool)
  case integer(Int)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])
}

extension JSONValue: Encodable {
  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case let .bool(value): try container.encode(value)
    case let .integer(value): try container.encode(value)
    case let .string(value): try container.encode(value)
    case let .array(value): try container.encode(value)
    case let .object(value): try container.encode(value)
    }
  }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
  init(stringLiteral value: String) { self = .string(value) }
  init(integerLiteral value: Int) { self = .integer(value) }
  init(booleanLiteral value: Bool) { self = .bool(value) }
  init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
  init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(elements, uniquingKeysWith: { $1 })) }
}

extension JSONValue {
  /// The value as bytes with sorted keys: the same value always gives the same bytes.
  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }

  subscript(key: String) -> JSONValue? {
    if case let .object(members) = self { members[key] } else { nil }
  }
}

/// JSON Schema pieces, so each schema reads as what it describes.
enum Schema {
  static func ref(_ name: String) -> JSONValue { ["$ref": .string("#/components/schemas/" + name)] }
  static func string(enum values: [String]? = nil, pattern: String? = nil, description: String? = nil) -> JSONValue {
    var members: [String: JSONValue] = ["type": "string"]
    if let values { members["enum"] = .array(values.map(JSONValue.string)) }
    if let pattern { members["pattern"] = .string(pattern) }
    if let description { members["description"] = .string(description) }
    return .object(members)
  }
  static func integer(minimum: Int? = nil, maximum: Int? = nil, description: String? = nil) -> JSONValue {
    var members: [String: JSONValue] = ["type": "integer"]
    if let minimum { members["minimum"] = .integer(minimum) }
    if let maximum { members["maximum"] = .integer(maximum) }
    if let description { members["description"] = .string(description) }
    return .object(members)
  }
  static var boolean: JSONValue { ["type": "boolean"] }
  static func array(of items: JSONValue) -> JSONValue { ["type": "array", "items": items] }
  static func constant(_ value: String) -> JSONValue { ["type": "string", "const": .string(value)] }
  /// `schema` or null.
  static func nullable(_ schema: JSONValue) -> JSONValue { ["oneOf": [schema, ["type": "null"]]] }
  /// An object that allows exactly the properties it names; `required` are the ones always present.
  static func object(_ properties: [String: JSONValue], required: [String], description: String? = nil) -> JSONValue {
    var members: [String: JSONValue] = [
      "type": "object",
      "properties": .object(properties),
      "required": .array(required.sorted().map(JSONValue.string)),
      "additionalProperties": false
    ]
    if let description { members["description"] = .string(description) }
    return .object(members)
  }
}
