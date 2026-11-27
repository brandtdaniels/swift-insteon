import InsteonProtocol

/// How a group command's ALL-Link cleanups went, from ``Modem/sendAllLinkCommand(group:command:wait:)``.
///
/// After broadcasting a group command, the modem sends each member of the group a cleanup
/// message of its own, in the order the members were added to its ALL-Link database. Each
/// member acknowledges its cleanup, or the modem reports that it didn't. A member that didn't
/// acknowledge its cleanup may still have acted on the broadcast.
///
/// Two reports are equal when they say the same about the members: ``statusReportAfter`` and
/// ``failureReportedAfter`` say how long the modem took, not what happened, so they are not compared.
public struct AllLinkCleanupReport: Hashable, Sendable {

  /// The members that acknowledged their cleanup, in the order they answered.
  public var acknowledged: [InsteonAddress]

  /// The members that didn't acknowledge their cleanup: those the modem reported as not
  /// answering, and those that answered with a NAK. In the order the modem reported them.
  public var unacknowledged: [InsteonAddress]

  /// Whether the modem sent every member its cleanup. `false` if it stopped partway, which the
  /// Insteon Developer's Guide says is normal when other Insteon traffic is detected; the members
  /// it didn't reach are in neither list.
  public var isComplete: Bool

  /// How long after the modem accepted the command its ALL-Link Cleanup Status Report (`0x58`)
  /// came, or `nil` if it didn't come in time or the modem doesn't measure.
  public var statusReportAfter: Duration?

  /// How long after the modem accepted the command the first ALL-Link Cleanup Failure Report
  /// (`0x56`) came, or `nil` if none did or the modem doesn't measure.
  public var failureReportedAfter: Duration?

  /// Creates a cleanup report.
  ///
  /// - Parameters:
  ///   - acknowledged: The members that acknowledged their cleanup.
  ///   - unacknowledged: The members that didn't.
  ///   - isComplete: Whether every member was sent its cleanup.
  ///   - statusReportAfter: How long the status report took, if it came.
  ///   - failureReportedAfter: How long the first failure report took, if one came.
  public init(acknowledged: [InsteonAddress], unacknowledged: [InsteonAddress], isComplete: Bool, statusReportAfter: Duration? = nil, failureReportedAfter: Duration? = nil) {

    self.acknowledged = acknowledged
    self.unacknowledged = unacknowledged
    self.isComplete = isComplete
    self.statusReportAfter = statusReportAfter
    self.failureReportedAfter = failureReportedAfter

  }

  public static func == (left: Self, right: Self) -> Bool {

    left.acknowledged == right.acknowledged && left.unacknowledged == right.unacknowledged && left.isComplete == right.isComplete

  }

  public func hash(into hasher: inout Hasher) {

    hasher.combine(acknowledged)
    hasher.combine(unacknowledged)
    hasher.combine(isComplete)

  }

}
