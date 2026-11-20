import Foundation

/// A `notification` event: a rule fired.
public struct NotificationEvent: Sendable, Equatable {
  /// The event's id on the stream, `<runId>-<sequence>`.
  public let id: String
  /// The rule's identifier.
  public let ruleID: String
  /// The rule's name.
  public let ruleName: String
  /// The device's address.
  public let address: String?
  /// When the rule fired, as the service wrote it.
  public let firedAt: String
  /// What fired the rule, such as `wet`, present only when the rule includes detail.
  public let event: String?

  /// Creates an event.
  public init(id: String, ruleID: String, ruleName: String, address: String?, firedAt: String, event: String?) {
    self.id = id
    self.ruleID = ruleID
    self.ruleName = ruleName
    self.address = address
    self.firedAt = firedAt
    self.event = event
  }
}

/// What a notifier acts on from the service's stream.
public enum StreamItem: Sendable, Equatable {
  /// The service accepted the connection and subscribed it. It is the first thing a stream sends.
  case connected
  /// A rule fired.
  case notification(NotificationEvent)
  /// The service can't replay what the client missed. `id` is the stream's current position.
  case gap(id: String?)
  /// An event of any other kind, or one this library doesn't read. `id` marks the client's place.
  case other(id: String?)

  /// Reads an event of the stream. A keepalive, and a block without an `id` and without data, read as nothing.
  public init?(_ event: ServerSentEvent) {
    guard let text = event.data else {
      if let id = event.id {
        self = .other(id: id)
      } else if event.comment == "connected" {
        self = .connected
      } else {
        return nil
      }
      return
    }
    guard let frame = try? JSONDecoder().decode(Frame.self, from: Data(text.utf8)) else {
      self = .other(id: event.id)
      return
    }
    switch frame.kind {
    case "gap":
      self = .gap(id: event.id)
    case "notification":
      guard let id = event.id, let ruleID = frame.ruleId, let name = frame.ruleName, let firedAt = frame.firedAt else {
        self = .other(id: event.id)
        return
      }
      self = .notification(NotificationEvent(id: id, ruleID: ruleID, ruleName: name, address: frame.address, firedAt: firedAt, event: frame.name))
    default:
      self = .other(id: event.id)
    }
  }

  private struct Frame: Decodable {
    let kind: String
    let ruleId: String?
    let ruleName: String?
    let address: String?
    let firedAt: String?
    let name: String?
  }
}

/// A position on the stream: the run and the number within it.
struct StreamPosition: Equatable {
  let run: String
  let sequence: Int

  /// Reads `<runId>-<sequence>`.
  init?(_ id: String) {
    guard let dash = id.lastIndex(of: "-"), let sequence = Int(id[id.index(after: dash)...]), dash != id.startIndex else { return nil }
    run = String(id[..<dash])
    self.sequence = sequence
  }

  /// Whether this position is later than `other` in the same run.
  func follows(_ other: StreamPosition) -> Bool { run == other.run && sequence > other.sequence }
}
