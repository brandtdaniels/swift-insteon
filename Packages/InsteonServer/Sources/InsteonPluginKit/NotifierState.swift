import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Where a notifier keeps the id of the last event it acted on, so a restart resumes instead of repeating.
public protocol NotifierStateStoring: Sendable {
  /// The stored id, or `nil` when none is stored.
  func lastEventID() throws -> String?
  /// Replaces the stored id.
  func record(lastEventID: String) throws
}

/// Why a notifier's state file couldn't be used.
public enum NotifierStateError: Error, Equatable, Sendable {
  /// The file exists but isn't a regular file this version reads, so it was left as it is.
  case unreadable
  /// The file couldn't be written.
  case unwritable
}

/// Keeps the id in a JSON file readable only by the current user.
///
/// A write goes to a temporary file in the same directory, which replaces the file in one step, so a
/// crash leaves the old id or the new one. A file that can't be read is left as it is.
public struct FileNotifierState: NotifierStateStoring {
  private let url: URL

  /// Creates a store.
  /// - Parameter url: The state file.
  public init(url: URL) {
    self.url = url
  }

  private struct Document: Codable {
    var version = 1
    var lastEventId: String
  }

  public func lastEventID() throws -> String? {
    var info = stat()
    guard lstat(url.path, &info) == 0 else {
      if errno == ENOENT { return nil }
      throw NotifierStateError.unreadable
    }
    guard (info.st_mode & S_IFMT) == S_IFREG, let data = FileManager.default.contents(atPath: url.path),
          let document = try? JSONDecoder().decode(Document.self, from: data), document.version == 1 else { throw NotifierStateError.unreadable }
    return document.lastEventId
  }

  public func record(lastEventID: String) throws {
    // Refuse to replace what lastEventID() would refuse to read.
    _ = try self.lastEventID()
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let data = try JSONEncoder().encode(Document(lastEventId: lastEventID))
    let temporary = directory.appendingPathComponent("." + url.lastPathComponent + "." + UUID().uuidString)
    guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw NotifierStateError.unwritable }
    guard rename(temporary.path, url.path) == 0 else {
      try? FileManager.default.removeItem(at: temporary)
      throw NotifierStateError.unwritable
    }
  }
}
