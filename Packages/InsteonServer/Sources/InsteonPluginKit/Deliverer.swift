import Foundation

/// What a notifier hands a delivery channel for one notification.
///
/// By default it carries the rule's name and the time and nothing else. A notifier that was told to
/// include detail adds the device and the event, which the service itself leaves out unless the rule
/// asks for it.
public struct DeliveryPayload: Sendable, Equatable {
  /// The rule's name.
  public let ruleName: String
  /// When the rule fired, as the service wrote it.
  public let firedAt: String
  /// The device's address, only when the notifier includes detail.
  public let address: String?
  /// What fired the rule, only when the notifier includes detail and the rule does.
  public let event: String?

  /// Creates a payload.
  public init(ruleName: String, firedAt: String, address: String? = nil, event: String? = nil) {
    self.ruleName = ruleName
    self.firedAt = firedAt
    self.address = address
    self.event = event
  }

  /// The payload as one line of text: the time, the name, and the detail when there is any, separated by tabs.
  /// A control character in a field becomes a space, so a field can't start another line.
  public var line: String {
    ([firedAt, ruleName] + [address, event].compactMap { $0 }).map(Self.flattened).joined(separator: "\t")
  }

  private static func flattened(_ text: String) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : $0 }))
  }
}

/// A channel that turns one notification into a delivery: a push, an email, a webhook or a line in a file.
///
/// A deliverer throws when the delivery didn't happen. The notifier retries it with backoff and
/// keeps its place, so a delivery that eventually succeeds is made once.
public protocol Deliverer: Sendable {
  /// Delivers the payload.
  func deliver(_ payload: DeliveryPayload) async throws
}

/// Appends each notification as one line to a file or to standard output.
public struct LineDeliverer: Deliverer {
  private let write: @Sendable (String) throws -> Void

  /// Creates a deliverer that passes each line to `write`.
  public init(write: @escaping @Sendable (String) throws -> Void) {
    self.write = write
  }

  /// A deliverer that appends to the file at `url`, creating it readable only by the current user.
  public static func appending(to url: URL) -> LineDeliverer {
    LineDeliverer { line in
      if !FileManager.default.fileExists(atPath: url.path) {
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
      }
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: Data((line + "\n").utf8))
    }
  }

  /// A deliverer that prints to standard output.
  public static var standardOutput: LineDeliverer {
    LineDeliverer { line in try FileHandle.standardOutput.write(contentsOf: Data((line + "\n").utf8)) }
  }

  public func deliver(_ payload: DeliveryPayload) async throws {
    try write(payload.line)
  }
}
