import Foundation
import InsteonProtocol
import InsteonService

/// One frame of a server-sent event stream, before its data is read.
struct EventFrame: Equatable {
  /// The `id` field, which for the service is a cursor's token.
  var id: String?
  /// The `event` field, which the service doesn't set: its data names the kind.
  var event: String?
  /// The `data` fields, joined with a line feed.
  var data: String?
}

/// Reads server-sent event frames from the bytes of a stream, however the bytes are cut.
///
/// A line ends with a line feed, a carriage return, or both. A blank line ends a frame. A line that
/// starts with a colon is a comment, such as the service's keepalive, and is dropped. A frame with
/// an `id` and no data is kept: it sets the reader's place.
struct ServerSentEventParser {

  private var pending: [UInt8] = []
  private var frame = EventFrame()
  private var hasFields = false
  private var atStart = true

  /// Takes the next bytes and returns the frames they finish.
  mutating func feed(_ data: Data) -> [EventFrame] {
    pending.append(contentsOf: data)
    if atStart {
      // A byte order mark that starts the stream isn't part of it.
      if pending.count < 3, [0xEF, 0xBB, 0xBF].starts(with: pending) { return [] }
      if pending.starts(with: [0xEF, 0xBB, 0xBF]) { pending.removeFirst(3) }
      atStart = false
    }
    var frames: [EventFrame] = []
    var start = 0
    var index = 0
    while index < pending.count {
      let byte = pending[index]
      guard byte == 0x0A || byte == 0x0D else { index += 1; continue }
      // A carriage return at the end may be the first half of a pair: wait for the next byte.
      if byte == 0x0D, index + 1 == pending.count { break }
      let line = pending[start..<index]
      index += (byte == 0x0D && pending[index + 1] == 0x0A) ? 2 : 1
      start = index
      if let finished = take(line: line) { frames.append(finished) }
    }
    pending.removeFirst(start)
    return frames
  }

  /// Applies one line, and returns the frame it ends, if it ends one.
  private mutating func take(line: ArraySlice<UInt8>) -> EventFrame? {
    if line.isEmpty {
      defer { frame = EventFrame(); hasFields = false }
      return hasFields ? frame : nil
    }
    if line.first == 0x3A { return nil }
    let text = String(decoding: line, as: UTF8.self)
    let name: Substring
    var value: Substring
    if let colon = text.firstIndex(of: ":") {
      name = text[..<colon]
      value = text[text.index(after: colon)...]
      if value.first == " " { value.removeFirst() }
    } else {
      name = text[...]
      value = ""
    }
    switch name {
    case "id":
      guard !value.contains("\0") else { return nil }
      frame.id = String(value)
      hasFields = true
    case "event":
      frame.event = String(value)
      hasFields = true
    case "data":
      frame.data = frame.data.map { $0 + "\n" + value } ?? String(value)
      hasFields = true
    default: break
    }
    return nil
  }

}

/// What the service writes in a frame's `data`, and what a client makes of it.
enum ServiceEventFrame {

  /// The item a frame stands for, or `nil` for a frame that sets nothing.
  ///
  /// A frame with an `id` and no data, and a frame of a kind or version this library can't
  /// represent, set the reader's place and are items of their own, so the cursor moves past them.
  ///
  /// - Throws: ``ConnectionPathError/badResponse`` for an id that isn't a cursor or data that isn't
  ///   the service's JSON.
  static func item(for frame: EventFrame) throws -> SequencedItem? {
    var cursor: EventCursor?
    if let id = frame.id, !id.isEmpty {
      guard let parsed = EventCursor(token: id) else { throw ConnectionPathError.badResponse }
      cursor = parsed
    }
    guard let text = frame.data else { return cursor.map { .position($0) } }
    let wire: Wire
    do {
      wire = try JSONDecoder().decode(Wire.self, from: Data(text.utf8))
    } catch {
      throw ConnectionPathError.badResponse
    }
    guard wire.version == 1 else { return cursor.map { .position($0) } }
    guard let place = cursor ?? wire.cursor else { throw ConnectionPathError.badResponse }
    if wire.kind == "gap" {
      return .gap(wire.reason.flatMap(EventGapReason.init(rawValue:)) ?? .otherRun, current: wire.cursor ?? place)
    }
    guard let event = try wire.event() else { return .position(place) }
    return .event(event, place)
  }

  /// The JSON of one `data` line.
  private struct Wire: Decodable {
    let version: Int
    let runId: String?
    let sequence: UInt64?
    let kind: String
    let address: String?
    let group: Int?
    let name: String?
    let productName: String?
    let completion: Completion?
    let cause: String?
    let ruleId: String?
    let ruleName: String?
    let firedAt: String?
    let scheduleId: String?
    let source: String?
    let outcome: String?
    let reason: String?
    let nextRun: String?

    var cursor: EventCursor? {
      guard let runId, let sequence else { return nil }
      return EventCursor(runID: runId, sequence: sequence)
    }

    struct Completion: Decodable {
      let action: String
      let levelPercent: Int?
      let result: WireReceipt
    }

    /// The service's event, `nil` for a kind this library has no case for.
    func event() throws -> ServiceEvent? {
      switch kind {
      case "commandCompleted":
        guard let completion, let action = Self.action(completion.action) else { throw ConnectionPathError.badResponse }
        let receipt = try completion.result.receipt()
        return .commandCompleted(ServiceCommand(address: receipt.address, action: action, levelPercent: completion.levelPercent), receipt)
      case "identified": return try device().map { .identified($0, productName: productName) }
      case "setButtonPressed": return try device().map { .setButtonPressed($0) }
      case "groupCommand":
        guard let group, let device = try device() else { return nil }
        return .groupCommand(device, group: group, name: name)
      case "heartbeat": return try device().map { .heartbeat($0, group: group) }
      case "statusChanged": return try device().map { .statusChanged($0) }
      case "modemUnavailable": return Self.unavailability(cause).map { .modemUnavailable($0) }
      case "reconnected": return .modemReconnected
      case "notification":
        guard let device = try device(), let ruleId, let ruleName, let fired = firedAt.flatMap(Self.date) else { return nil }
        return .notification(ServiceNotification(ruleID: ruleId, ruleName: ruleName, device: device, firedAt: fired, eventName: name))
      case "schedule": return try schedule()
      default: return nil
      }
    }

    private func device() throws -> InsteonAddress? {
      guard let address else { return nil }
      guard let parsed = InsteonAddress(address) else { throw ConnectionPathError.badResponse }
      return parsed
    }

    private func schedule() throws -> ServiceEvent? {
      guard let device = try device(), let scheduleId, let name, let fired = firedAt.flatMap(Self.date),
        let source = source.flatMap({ $0 == "timer" ? ScheduleRun.Source.timer : $0 == "schedule" ? .schedule : nil }),
        let outcome = outcome.flatMap(scheduleOutcome)
      else { return nil }
      return .schedule(ScheduleRun(source: source, id: scheduleId, name: name, device: device, outcome: outcome, firedAt: fired, nextRun: nextRun.flatMap(Self.date)))
    }

    private func scheduleOutcome(_ name: String) -> ScheduleRun.Outcome? {
      switch name {
      case "acknowledged": .acknowledged
      case "missed": .missed
      case "unknown": .unknown
      case "unavailable": Self.unavailability(cause).map { .unavailable($0) }
      case "refused":
        switch reason {
        case "unknownDevice": .refused(.unknownDevice)
        case "invalidLevel": .refused(.invalidLevel)
        case "unsupportedControl": .refused(.unsupportedControl)
        case "notIdentified": .refused(.notIdentified)
        case "notLinked": .refused(.notLinked)
        case "busy": .refused(.busy)
        default: nil
        }
      default: nil
      }
    }

    private static func action(_ name: String) -> ServiceCommand.Action? {
      switch name {
      case "identify": .identify
      case "status": .status
      case "on": .on
      case "off": .off
      default: nil
      }
    }

    /// The cause as a case. A Hub's error status isn't on the wire, so that case carries 0.
    private static func unavailability(_ name: String?) -> ModemUnavailability? {
      switch name {
      case "connecting": .connecting
      case "hubUnreachable": .hubUnreachable
      case "credentialsRejected": .credentialsRejected
      case "hubErrorStatus": .hubErrorStatus(0)
      case "modemUnreachable": .modemUnreachable
      case "connectionLost": .connectionLost
      default: nil
      }
    }

    /// An ISO 8601 date, with or without fractional seconds.
    private static func date(_ text: String) -> Date? {
      let plain = ISO8601DateFormatter()
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return plain.date(from: text) ?? fractional.date(from: text)
    }
  }

}

/// Reads the numbered items of one event stream from its bytes, one at a time.
actor EventStreamReader {

  private let chunks: AsyncThrowingStream<Data, any Error>
  private var parser = ServerSentEventParser()
  private var ready: [SequencedItem] = []

  init(chunks: AsyncThrowingStream<Data, any Error>) {
    self.chunks = chunks
  }

  /// The next item, or `nil` when the service closes the stream or the reading is canceled.
  ///
  /// - Throws: ``ConnectionPathError/interrupted`` when the connection fails, or
  ///   ``ConnectionPathError/badResponse`` for a frame that isn't the service's.
  func next() async throws -> SequencedItem? {
    while true {
      if !ready.isEmpty { return ready.removeFirst() }
      var chunk: Data?
      do {
        // Each read takes the next chunk the stream holds; the stream is read by one reader.
        for try await next in chunks {
          chunk = next
          break
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw ConnectionPathError.interrupted
      }
      guard let chunk else { return nil }
      for frame in parser.feed(chunk) {
        if let item = try ServiceEventFrame.item(for: frame) { ready.append(item) }
      }
    }
  }

}
