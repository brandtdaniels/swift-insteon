import InsteonCore
import InsteonService

/// The fixed strings the JSON API and the event stream use, as enumerations, so the wire format and
/// its description are made from the same list.

/// What a command receipt says happened.
enum ReceiptOutcome: String, CaseIterable, Sendable {
  case acknowledged, read
}

/// How the snapshot was saved, independent of the device result.
enum PersistenceName: String, CaseIterable, Sendable {
  case notConfigured, notAttempted, saved, failed

  init(_ outcome: PersistenceOutcome) {
    switch outcome {
    case .notConfigured: self = .notConfigured
    case .notAttempted: self = .notAttempted
    case .saved: self = .saved
    case .failed: self = .failed
    }
  }
}

/// How a status reading is expressed.
enum ReadingKind: String, CaseIterable, Sendable {
  case percent, onOff, named, raw
}

/// The service's readiness.
enum HealthStatusName: String, CaseIterable, Sendable {
  case starting, ready, degraded
}

/// The kinds of frame on the event stream.
enum EventKind: String, CaseIterable, Sendable {
  case commandCompleted, identified, setButtonPressed, groupCommand, heartbeat, statusChanged
  case modemUnavailable, reconnected
  /// A notification rule fired.
  case notification
  /// A schedule or a timer ran, or a run was missed.
  case schedule
  /// A scene ran.
  case scene
  /// A scene's members were changed by applying a plan, in whole or in part.
  case sceneMembership
  /// The client missed events the server can't replay.
  case gap
}

/// What a health note is about.
enum HealthNoteCode: String, CaseIterable, Sendable {
  case timeZoneUnavailable, hubClockDrift
}

/// What a run of a schedule or a timer came to.
enum ScheduleOutcomeName: String, CaseIterable, Sendable {
  case acknowledged, missed, unavailable, refused, unknown
}

/// Whether a schedule or a timer ran.
enum ScheduleSourceName: String, CaseIterable, Sendable {
  case schedule, timer
}

/// What started a scene run.
enum SceneSourceName: String, CaseIterable, Sendable {
  case api
}

/// How a schedule's time of day is written.
enum ScheduleTimeKind: String, CaseIterable, Sendable {
  case clock, sunrise, sunset
}

/// What a scheduled action does.
enum ScheduleActionName: String, CaseIterable, Sendable {
  case on, off
}

/// The days of the week, as a schedule writes them.
enum WeekdayName: String, CaseIterable, Sendable {
  case sunday, monday, tuesday, wednesday, thursday, friday, saturday
}

/// What makes a notification rule fire.
enum NotificationTriggerKind: String, CaseIterable, Sendable {
  case event, groupCommand
}

extension ModemUnavailability {
  /// Every cause's wire name. Adding a case to ``ModemUnavailability`` fails to compile here until it is listed.
  static var allWireNames: [String] {
    let samples: [ModemUnavailability] = [.connecting, .hubUnreachable, .credentialsRejected, .hubErrorStatus(0), .modemUnreachable, .connectionLost]
    for sample in samples {
      switch sample {
      case .connecting, .hubUnreachable, .credentialsRejected, .hubErrorStatus, .modemUnreachable, .connectionLost: break
      }
    }
    return samples.map(\.wireName)
  }
}
