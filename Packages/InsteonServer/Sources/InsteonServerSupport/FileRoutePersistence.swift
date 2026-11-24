import Foundation
import InsteonHTTP

/// Keeps the routes transports registered in a JSON file readable only by the current user.
///
/// The file sits beside the state file, because the state file's format is the device network's. It
/// holds each route's kind and ticket and no credential. A file that can't be read, is in a newer
/// format or is not a regular file is left as it is. The routes are hints a client tries in order,
/// so the file is read again on every use: `insteon-server pair` sees what a running server holds.
struct FileRoutePersistence: RoutePersisting {
  let url: URL

  /// The routes file for a state file: the same directory and name, ending in `-routes.json`.
  static func url(besideState statePath: String) -> URL {
    let state = URL(fileURLWithPath: statePath)
    return state.deletingLastPathComponent().appendingPathComponent(state.deletingPathExtension().lastPathComponent + "-routes.json")
  }

  private var file: PrivateJSONFile<RouteRegistry> { PrivateJSONFile(url: url, accepts: { $0.version == 1 }) }

  func load() throws -> RouteRegistry? { try file.load() }

  func save(_ registry: RouteRegistry) throws { try file.save(registry) }
}
