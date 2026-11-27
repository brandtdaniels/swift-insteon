import InsteonCore
import InsteonProtocol
import InsteonService

/// A command's receipt as the service writes it, in an answer and in a `commandCompleted` event.
struct WireReceipt: Decodable {
  let address: String
  let outcome: String
  let status: Status?
  let persistence: String

  struct Status: Decodable {
    let group: Int?
    let kind: String
    let value: UInt8
    let isOn: Bool
    let percent: Int?
    let label: String?
  }

  /// The receipt, or a bad response for anything the service's contract doesn't allow.
  func receipt() throws -> CommandReceipt {
    guard let address = InsteonAddress(address) else { throw ConnectionPathError.badResponse }
    let outcome: CommandReceipt.Outcome
    switch self.outcome {
    case "read": outcome = .read
    case "acknowledged": outcome = .acknowledged
    default: throw ConnectionPathError.badResponse
    }
    let persistence: PersistenceOutcome
    switch self.persistence {
    case "notConfigured": persistence = .notConfigured
    case "notAttempted": persistence = .notAttempted
    case "saved": persistence = .saved
    case "failed": persistence = .failed
    default: throw ConnectionPathError.badResponse
    }
    // A status accompanies a read, and only a read.
    if status != nil, outcome != .read { throw ConnectionPathError.badResponse }
    return CommandReceipt(address: address, outcome: outcome, status: try status.map(Self.deviceStatus), persistence: persistence)
  }

  /// The service's status carries no ALL-Link database delta, so the delta is 0 here.
  private static func deviceStatus(_ status: Status) throws -> DeviceStatus {
    let reading: DeviceStatus.Reading
    switch status.kind {
    case "percent":
      guard let percent = status.percent else { throw ConnectionPathError.badResponse }
      reading = .percent(percent)
    case "onOff": reading = .onOff(status.isOn)
    case "named":
      guard let label = status.label else { throw ConnectionPathError.badResponse }
      reading = .named(label)
    case "raw": reading = .raw
    default: throw ConnectionPathError.badResponse
    }
    return DeviceStatus(group: status.group, value: status.value, allLinkDatabaseDelta: 0, reading: reading, isOn: status.isOn)
  }
}
