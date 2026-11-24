import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A JSON document in a file readable only by the current user.
///
/// A file that can't be read, doesn't decode, isn't `accepts`ed or is not a regular file is left as it
/// is: ``save(_:)`` refuses to replace what ``load()`` refuses to read. A write goes to a temporary
/// file in the same directory, which replaces the file in one step, so a reader never sees half a
/// document.
struct PrivateJSONFile<Document: Codable & Sendable>: Sendable {
  let url: URL
  /// Whether a decoded document is one this server reads, such as one of the format's version.
  let accepts: @Sendable (Document) -> Bool

  /// Why the file couldn't be used.
  enum FileError: Error { case unreadable, unwritable }

  /// The stored document, or `nil` when there is no file.
  func load() throws -> Document? {
    var info = stat()
    guard lstat(url.path, &info) == 0 else {
      if errno == ENOENT { return nil }
      throw FileError.unreadable
    }
    guard (info.st_mode & S_IFMT) == S_IFREG, let data = FileManager.default.contents(atPath: url.path) else { throw FileError.unreadable }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let document = try? decoder.decode(Document.self, from: data), accepts(document) else { throw FileError.unreadable }
    return document
  }

  /// Replaces the stored document.
  func save(_ document: Document) throws {
    // Refuse to replace what load() would refuse to read.
    _ = try load()
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(document)
    let temporary = directory.appendingPathComponent("." + url.lastPathComponent + "." + UUID().uuidString)
    guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw FileError.unwritable }
    guard rename(temporary.path, url.path) == 0 else {
      try? FileManager.default.removeItem(at: temporary)
      throw FileError.unwritable
    }
  }
}
