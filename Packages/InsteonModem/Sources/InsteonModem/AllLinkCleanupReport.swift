import InsteonProtocol

/// How a group command's ALL-Link cleanups went, from ``Modem/sendAllLinkCommand(group:command:timeout:)``.
///
/// After broadcasting a group command, the modem sends each member of the group a cleanup
/// message of its own, in the order the members were added to its ALL-Link database. Each
/// member acknowledges its cleanup, or the modem reports that it didn't. A member that didn't
/// acknowledge its cleanup may still have acted on the broadcast.
public struct AllLinkCleanupReport: Hashable, Sendable {

  /// The members that acknowledged their cleanup, in the order they answered.
  public var acknowledged: [InsteonAddress]

  /// The members that didn't acknowledge their cleanup: those the modem reported as not
  /// answering, and those that answered with a NAK. In the order the modem reported them.
  public var unacknowledged: [InsteonAddress]

  /// Whether the modem sent every member its cleanup. `false` if it stopped partway, which the
  /// Developer's Guide says is normal when other Insteon traffic is detected; the members it
  /// didn't reach are in neither list.
  public var isComplete: Bool

  /// Creates a cleanup report.
  ///
  /// - Parameters:
  ///   - acknowledged: The members that acknowledged their cleanup.
  ///   - unacknowledged: The members that didn't.
  ///   - isComplete: Whether every member was sent its cleanup.
  public init(acknowledged: [InsteonAddress], unacknowledged: [InsteonAddress], isComplete: Bool) {

    self.acknowledged = acknowledged
    self.unacknowledged = unacknowledged
    self.isComplete = isComplete

  }

}
