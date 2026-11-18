import HTTPTypes
import InsteonService

/// The stable vocabulary of failures a client can branch on.
///
/// Every failure the server reports has one code, and the request log carries the same string, so
/// a client's report and the log line for it match. Each code has one HTTP status, except
/// ``requestRejected``, which reports the status the transport chose. ``sent`` says whether a
/// command that changes a device may have reached it.
enum APIErrorCode: String, CaseIterable, Sendable {
  case authenticationRequired
  case authenticationFailed
  case invalidAddress
  case invalidCommand
  case invalidLevel
  case unknownDevice
  case routeNotFound
  case apiMarkerMissing
  case formKeyInvalid
  case bodyTooLarge
  case unsupportedMediaType
  case requestRejected
  case busy
  case notIdentified
  case notLinked
  case unsupportedControl
  case deviceRejected
  case modemRejected
  case modemUnavailable
  case deviceNotAnswering
  case outcomeUnknown
  case canceled

  /// The status the code answers with.
  var status: HTTPResponse.Status {
    switch self {
    case .authenticationRequired, .authenticationFailed: .unauthorized
    case .invalidAddress, .invalidCommand, .invalidLevel: .badRequest
    case .unknownDevice, .routeNotFound: .notFound
    case .apiMarkerMissing, .formKeyInvalid: .forbidden
    case .bodyTooLarge: .contentTooLarge
    case .unsupportedMediaType: .unsupportedMediaType
    case .requestRejected: .badRequest
    case .busy, .notIdentified, .notLinked: .conflict
    case .unsupportedControl, .deviceRejected: .unprocessableContent
    case .modemRejected, .modemUnavailable, .canceled: .serviceUnavailable
    case .deviceNotAnswering: .gatewayTimeout
    case .outcomeUnknown: .badGateway
    }
  }

  /// Whether a command that changes a device may have reached it. A read, a refusal and a device's
  /// own rejection report `false`, because repeating them is safe. Only a control that failed
  /// without a definite answer, or one canceled in flight, reports `true`.
  var sent: Bool {
    switch self {
    case .outcomeUnknown, .canceled: true
    default: false
    }
  }

  /// The explanation a person reads, without a device address, host or credential.
  var message: String {
    switch self {
    case .authenticationRequired: "Authentication required."
    case .authenticationFailed: "The credentials were not accepted."
    case .invalidAddress: "The device address is not a valid Insteon address."
    case .invalidCommand: "Invalid command."
    case .invalidLevel: "The device or action does not accept that percentage."
    case .unknownDevice: "Unknown device."
    case .routeNotFound: "No such route."
    case .apiMarkerMissing: "An explicit API request is required."
    case .formKeyInvalid: "The form expired. Reload the page and try again."
    case .bodyTooLarge: "Request body too large."
    case .unsupportedMediaType: "Unsupported content type."
    case .requestRejected: "Invalid request."
    case .busy: "The service is busy. Try again explicitly; nothing was queued."
    case .notIdentified: "The device has not reported what it is, so no control was sent. Identify it, or try again when it is awake."
    case .notLinked: "The device rejected the modem because it is not linked to it. Link it first. Nothing changed."
    case .unsupportedControl: "The device does not support that control."
    case .deviceRejected: "The device rejected the command. Nothing changed."
    case .modemRejected: "The modem refused the command. Nothing was sent; try again."
    case .modemUnavailable: "The modem is not connected. Nothing was sent."
    case .deviceNotAnswering: "The device did not answer. A read changes nothing, so it is safe to try again."
    case .outcomeUnknown: "The control may have reached the device, and its outcome is unknown. Read status before repeating it."
    case .canceled: "Request canceled. Its hardware outcome may be unknown; read status before retrying."
    }
  }
}

/// A command that failed after it was accepted, with what it was asking for, so the failure can be
/// classified as a read or a control.
struct CommandFailure: Error {
  let action: ServiceCommand.Action
  let underlying: any Error
}
