import Foundation
import InsteonHTTP

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

  private var file: PrivateJSONFile<ClientRegistry> { PrivateJSONFile(url: url, accepts: { $0.version == 1 }) }

  func load() async throws -> ClientRegistry? { try file.load() }

  func save(_ registry: ClientRegistry) async throws { try file.save(registry) }
}
