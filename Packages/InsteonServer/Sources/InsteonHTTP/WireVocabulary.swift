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
  /// The client missed events the server can't replay.
  case gap
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
