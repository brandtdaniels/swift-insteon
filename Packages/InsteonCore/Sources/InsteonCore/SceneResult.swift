import InsteonModem
import InsteonProtocol

/// How a modem scene's command reached the group's responders, from
/// ``ModemScene/send(turningOn:responderCount:through:)``.
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

  /// Creates a scene result.
  ///
  /// - Parameters:
  ///   - acknowledged: The responders that acknowledged their cleanup.
  ///   - unacknowledged: The responders that didn't.
  ///   - isComplete: Whether every responder was sent its cleanup.
  public init(acknowledged: [InsteonAddress], unacknowledged: [InsteonAddress], isComplete: Bool) {

    self.acknowledged = acknowledged
    self.unacknowledged = unacknowledged
    self.isComplete = isComplete

  }

  /// The result the modem's cleanup report gives.
  init(_ report: AllLinkCleanupReport) {

    self.init(acknowledged: report.acknowledged, unacknowledged: report.unacknowledged, isComplete: report.isComplete)

  }

}
