import Foundation
import InsteonHTTP
import InsteonScheduling
import InsteonService

/// Keeps the schedules, the timers and the home's place in a JSON file readable only by the current user.
///
/// The file sits beside the state file, because the state file's format is the device network's. It holds
/// each schedule and timer, the time every timer has left, the last moment the service looked for runs, and
/// the time zone and location the server ran with, and no credential. A file that can't be read, is in a
/// newer format or is not a regular file is left as it is.
struct FileSchedulePersistence: ScheduleStoring {
  let url: URL

  /// The schedules file for a state file: the same directory and name, ending in `-schedules.json`.
  static func url(besideState statePath: String) -> URL {
    let state = URL(fileURLWithPath: statePath)
    return state.deletingLastPathComponent().appendingPathComponent(state.deletingPathExtension().lastPathComponent + "-schedules.json")
  }

  private var file: PrivateJSONFile<ScheduleDocument> { PrivateJSONFile(url: url, accepts: { $0.version == 1 && (try? $0.stored()) != nil }) }

  func load() async throws -> StoredSchedules? {
    try file.load()?.stored()
  }

  func save(_ stored: StoredSchedules) async throws {
    try file.save(ScheduleDocument(stored))
  }
}

/// What the schedules file holds.
struct ScheduleDocument: Codable, Sendable, Equatable {
  /// A timer and the seconds it had left.
  struct Timer: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let delaySeconds: Int
    let action: ScheduledActionRecord
    let remainingSeconds: Double
  }

  /// The time zone and location the server ran with.
  struct Settings: Codable, Sendable, Equatable {
    let timeZone: String?
    let latitude: Double?
    let longitude: Double?
  }

  /// The file's format.
  var version = 1
  var schedules: [ScheduleRecord]
  var timers: [Timer]
  var checkedThrough: Date?
  var settings: Settings

  init(_ stored: StoredSchedules) {
    schedules = stored.schedules.map { ScheduleRecord($0) }
    timers = stored.timers.map { Timer(id: $0.timer.id, name: $0.timer.name, delaySeconds: $0.timer.delaySeconds, action: ScheduledActionRecord($0.timer.action), remainingSeconds: $0.remainingSeconds) }
    checkedThrough = stored.checkedThrough
    settings = Settings(timeZone: stored.settings.timeZoneIdentifier, latitude: stored.settings.location?.latitude, longitude: stored.settings.location?.longitude)
  }

  /// The document as the service reads it.
  /// - Throws: An error when a record isn't a schedule or a timer.
  func stored() throws -> StoredSchedules {
    var location: GeographicCoordinate?
    switch (settings.latitude, settings.longitude) {
    case let (latitude?, longitude?):
      guard let coordinate = GeographicCoordinate(latitude: latitude, longitude: longitude) else { throw FileSchedulePersistence.Unreadable.record }
      location = coordinate
    case (nil, nil): break
    default: throw FileSchedulePersistence.Unreadable.record
    }
    return StoredSchedules(
      schedules: try schedules.map { try $0.schedule() },
      timers: try timers.map { StoredTimer(timer: ServiceTimer(id: $0.id, name: $0.name, delaySeconds: $0.delaySeconds, action: try $0.action.scheduledAction()), remainingSeconds: $0.remainingSeconds) },
      checkedThrough: checkedThrough,
      settings: ScheduleSettings(timeZoneIdentifier: settings.timeZone, location: location)
    )
  }
}

extension FileSchedulePersistence {
  /// A record in the file that isn't a schedule, a timer or a place.
  enum Unreadable: Error { case record }
}
