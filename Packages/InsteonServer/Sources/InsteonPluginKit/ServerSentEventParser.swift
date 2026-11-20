import Foundation

/// One block of a server-sent event stream: an `id`, `data` or both, or only a comment such as the
/// service's `: connected` greeting and its `: keepalive`.
public struct ServerSentEvent: Sendable, Equatable {
  /// The `id` field, which the client sends back as `Last-Event-ID`.
  public let id: String?
  /// The `data` lines joined by a newline.
  public let data: String?
  /// The text of a comment line, for a block that has only that.
  public let comment: String?

  /// Creates an event.
  public init(id: String?, data: String?, comment: String? = nil) {
    self.id = id
    self.data = data
    self.comment = comment
  }
}

/// Reads server-sent events from the bytes of a response, however they are split into chunks.
///
/// A line that starts with a colon is a comment. A block that holds only comments is an event with
/// the last comment's text. A blank line ends a block.
public struct ServerSentEventParser: Sendable {
  private var buffer = Data()
  private var id: String?
  private var data: [String] = []
  private var comment: String?

  /// Creates a parser.
  public init() {}

  /// Adds a chunk and returns the events it completed.
  public mutating func feed(_ chunk: Data) -> [ServerSentEvent] {
    buffer.append(chunk)
    var events: [ServerSentEvent] = []
    while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
      var line = buffer[buffer.startIndex..<newline]
      buffer.removeSubrange(buffer.startIndex...newline)
      if line.last == UInt8(ascii: "\r") { line = line.dropLast() }
      if line.isEmpty {
        if id != nil || !data.isEmpty {
          events.append(ServerSentEvent(id: id, data: data.isEmpty ? nil : data.joined(separator: "\n")))
        } else if let comment {
          events.append(ServerSentEvent(id: nil, data: nil, comment: comment))
        }
        id = nil
        data = []
        comment = nil
      } else if line.first == UInt8(ascii: ":") {
        comment = String(decoding: line.dropFirst(), as: UTF8.self).trimmingCharacters(in: .whitespaces)
      } else {
        read(String(decoding: line, as: UTF8.self))
      }
    }
    return events
  }

  private mutating func read(_ line: String) {
    let name: Substring, value: Substring
    if let colon = line.firstIndex(of: ":") {
      name = line[..<colon]
      var rest = line[line.index(after: colon)...]
      if rest.first == " " { rest = rest.dropFirst() }
      value = rest
    } else {
      name = line[...]
      value = ""
    }
    switch name {
    case "id": id = String(value)
    case "data": data.append(String(value))
    default: break
    }
  }
}
