import Foundation
import InsteonHTTP
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Keeps the client registry in a JSON file readable only by the current user.
///
/// The file holds each client's name, scope and a salted hash of its token, never a token. It sits
/// beside the state file, because the state file's format is the device network's. A file that
/// can't be read, is in a newer format or is not a regular file is left as it is.
struct FileClientPersistence: ClientPersisting {
  let url: URL

  /// The registry file for a state file: the same directory and name, ending in `-clients.json`.
  static func url(besideState statePath: String) -> URL {
    let state = URL(fileURLWithPath: statePath)
    return state.deletingLastPathComponent().appendingPathComponent(state.deletingPathExtension().lastPathComponent + "-clients.json")
  }

  func load() async throws -> ClientRegistry? {
    var info = stat()
    guard lstat(url.path, &info) == 0 else {
      if errno == ENOENT { return nil }
      throw FileError.unreadable
    }
    guard (info.st_mode & S_IFMT) == S_IFREG, let data = FileManager.default.contents(atPath: url.path) else { throw FileError.unreadable }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let registry = try? decoder.decode(ClientRegistry.self, from: data), registry.version == 1 else { throw FileError.unreadable }
    return registry
  }

  func save(_ registry: ClientRegistry) async throws {
    // Refuse to replace what load() would refuse to read.
    _ = try await load()
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(registry)
    let temporary = directory.appendingPathComponent("." + url.lastPathComponent + "." + UUID().uuidString)
    guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw FileError.unwritable }
    guard rename(temporary.path, url.path) == 0 else {
      try? FileManager.default.removeItem(at: temporary)
      throw FileError.unwritable
    }
  }

  private enum FileError: Error { case unreadable, unwritable }
}
