import Foundation

/// A cached device and the controls its main group supports. Values are not a live status.
public struct GatewayDevice: Codable, Equatable, Sendable {
  /// The device's Insteon address.
  public var address: String
  /// The catalog's product name, if known.
  public var productName: String?
  /// Whether the main group can be turned on and off.
  public var canTurnOnAndOff: Bool
  /// Whether the main group accepts a percentage.
  public var canDim: Bool
  /// The cached byte, interpreted only by a client that knows the device's capabilities.
  public var value: UInt8?
  /// When the device last answered a command, not when it was passively heard.
  public var lastAnsweredAt: Date?

  /// Creates a cached device description.
  public init(address: String, productName: String?, canTurnOnAndOff: Bool, canDim: Bool, value: UInt8?, lastAnsweredAt: Date?) {
    self.address = address
    self.productName = productName
    self.canTurnOnAndOff = canTurnOnAndOff
    self.canDim = canDim
    self.value = value
    self.lastAnsweredAt = lastAnsweredAt
  }
}

/// The versioned response to a device list request. Dates use ISO 8601 on the wire.
public struct GatewayDeviceList: Codable, Sendable {
  /// The response format's version.
  public let version: Int
  /// The known devices, in address order.
  public let devices: [GatewayDevice]

  /// Creates a version 1 response.
  public init(devices: [GatewayDevice]) {
    self.version = 1
    self.devices = devices
  }
}

/// An explicit operation on one known device's main group.
public struct GatewayCommand: Equatable, Sendable {
  /// The operations exposed by the gateway. Raw sends and linking are not exposed.
  public enum Action: String, Codable, Sendable {
    /// Ask the device for its identity.
    case identify
    /// Read the device's status.
    case status
    /// Turn the main group on, optionally at a percentage.
    case on
    /// Turn the main group off.
    case off
  }
  /// The device's Insteon address.
  public let address: String
  /// The operation requested.
  public let action: Action
  /// A percentage, accepted only for an On operation on a group that dims.
  public let levelPercent: Int?

  /// Creates a command. The gateway and controller validate it before use.
  public init(address: String, action: Action, levelPercent: Int? = nil) {
    self.address = address
    self.action = action
    self.levelPercent = levelPercent
  }
}

/// The result of a command, distinguishing a write acknowledgment from a status reading.
public struct GatewayCommandResult: Codable, Sendable {
  /// What the command established.
  public enum Outcome: String, Codable, Sendable {
    /// The device acknowledged a control command; its resulting state wasn't read back.
    case acknowledged
    /// The device answered a status or identification request.
    case read
  }
  /// The device that answered.
  public let address: String
  /// Whether this was an acknowledgment or a read.
  public let outcome: Outcome
  /// The status reading as interpreted by InsteonCore, for a status command only.
  public let status: String?

  /// Creates a command result.
  public init(address: String, outcome: Outcome, status: String?) {
    self.address = address
    self.outcome = outcome
    self.status = status
  }
}

/// A controller behind the authenticated request boundary.
public protocol GatewayControlling: Sendable {
  /// Lists cached devices without sending requests to hardware.
  func devices() async throws -> [GatewayDevice]
  /// Performs an explicit, validated command. It must not retry a control automatically.
  func perform(_ command: GatewayCommand) async throws -> GatewayCommandResult
}

/// An HTTP request represented independently of a server framework.
public struct GatewayRequest: Sendable {
  /// The HTTP method.
  public let method: String
  /// The path without a query or fragment.
  public let path: String
  /// Case-insensitive headers stored under lowercase names.
  public let headers: [String: String]
  /// The body, limited to 8 KiB by the gateway and its server adapter.
  public let body: Data

  /// Creates a request. Repeated header names are combined and fail authentication if ambiguous.
  public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
    self.method = method
    self.path = path
    self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { $0 + "," + $1 })
    self.body = body
  }
}

/// An HTTP response represented independently of a server framework.
public struct GatewayResponse: Sendable {
  /// The HTTP status code.
  public let status: Int
  /// Response headers, including cache and browser security policies.
  public let headers: [String: String]
  /// The encoded JSON, HTML or plain text.
  public let body: Data

  /// Creates a response with headers supplied by the gateway or server adapter.
  public init(status: Int, headers: [String: String], body: Data) {
    self.status = status
    self.headers = headers
    self.body = body
  }
}

/// An invalid gateway setup.
public enum GatewayConfigurationError: Error {
  /// A password needs 32 through 1024 bytes, and must not contain control characters.
  case weakPassword
  /// A form key must not be empty.
  case emptyFormKey
}

/// A command the controller cannot execute.
public enum GatewayControlError: Error {
  /// The address is invalid or absent from the controller's known devices.
  case unknownDevice
  /// A percentage is invalid, inapplicable to this action, or unsupported by the device.
  case invalidLevel
  /// The device doesn't support switching its main group.
  case unsupportedControl
  /// Another operation is using this controller. The caller may try again explicitly.
  case busy
}
