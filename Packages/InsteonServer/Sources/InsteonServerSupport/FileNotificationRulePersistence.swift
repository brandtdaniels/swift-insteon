import Foundation
import InsteonHTTP
import InsteonService

/// Keeps the notification rules in a JSON file readable only by the current user.
///
/// The file sits beside the state file, because the state file's format is the device network's. It holds
/// each rule's name, trigger, cooldown and flags, and no credential. A file that can't be read, is in a newer
/// format or is not a regular file is left as it is.
struct FileNotificationRulePersistence: NotificationRulePersisting {
  let url: URL

  /// The rules file for a state file: the same directory and name, ending in `-notification-rules.json`.
  static func url(besideState statePath: String) -> URL {
    let state = URL(fileURLWithPath: statePath)
    return state.deletingLastPathComponent().appendingPathComponent(state.deletingPathExtension().lastPathComponent + "-notification-rules.json")
  }

  private var file: PrivateJSONFile<NotificationRuleRegistry> { PrivateJSONFile(url: url, accepts: { $0.version == 1 }) }

  func load() async throws -> [ServiceNotificationRule]? {
    try file.load()?.rules.map { try $0.rule() }
  }

  func save(_ rules: [ServiceNotificationRule]) async throws {
    try file.save(NotificationRuleRegistry(rules: rules.map(NotificationRuleRecord.init)))
  }
}
