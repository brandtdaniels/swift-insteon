import InsteonModem
import InsteonProtocol

/// How a modem scene's command reached the group's responders, from
/// ``ModemScene/send(turningOn:through:wait:)``.
///
/// After broadcasting the command, the modem sends each responder a cleanup message of its
/// own. Each responder acknowledges its cleanup, or the modem reports that it didn't. A
/// responder that didn't acknowledge its cleanup may still have acted on the broadcast.
public struct SceneResult: Hashable, Sendable {

  /// The responders that acknowledged their cleanup, in the order they answered.
  public var acknowledged: [InsteonAddress]

  /// The responders that didn't acknowledge their cleanup, in the order the modem reported
  /// them.
  public var unacknowledged: [InsteonAddress]

  /// Whether the modem sent every responder its cleanup. `false` if it stopped partway, which
  /// the Insteon Developer's Guide says is normal when other Insteon traffic is detected; the
  /// responders it didn't reach are in neither list.
  public var isComplete: Bool

  /// How long after the modem accepted the command its ALL-Link Cleanup Status Report came, or
  /// `nil` if it didn't come in time.
  public var statusReportAfter: Duration?

  /// How long after the modem accepted the command the first ALL-Link Cleanup Failure Report
  /// came, or `nil` if none did.
  public var failureReportedAfter: Duration?

  /// How many controller records the modem holds for the group, so how many responders a missing
  /// report was expected from, a responder that doesn't answer included. It is `0` when the
  /// result didn't come from a network, which knows its modem's records.
  public var responderCount: Int

  /// Creates a scene result.
  ///
  /// - Parameters:
  ///   - acknowledged: The responders that acknowledged their cleanup.
  ///   - unacknowledged: The responders that didn't.
  ///   - isComplete: Whether every responder was sent its cleanup.
  ///   - statusReportAfter: How long the status report took, if it came.
  ///   - failureReportedAfter: How long the first failure report took, if one came.
  ///   - responderCount: How many controller records the modem holds for the group.
  public init(acknowledged: [InsteonAddress], unacknowledged: [InsteonAddress], isComplete: Bool, statusReportAfter: Duration? = nil, failureReportedAfter: Duration? = nil, responderCount: Int = 0) {

    self.responderCount = responderCount
    self.acknowledged = acknowledged
    self.unacknowledged = unacknowledged
    self.isComplete = isComplete
    self.statusReportAfter = statusReportAfter
    self.failureReportedAfter = failureReportedAfter

  }

  /// The result the modem's cleanup report gives.
  init(_ report: AllLinkCleanupReport) {

    self.init(acknowledged: report.acknowledged, unacknowledged: report.unacknowledged, isComplete: report.isComplete, statusReportAfter: report.statusReportAfter, failureReportedAfter: report.failureReportedAfter)

  }

}
