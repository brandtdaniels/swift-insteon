/// How long ``Modem/sendAllLinkCommand(group:command:wait:)`` waits.
///
/// The wait has four parts. After sending the command it waits up to ``echo`` for the modem to
/// accept it. After that it waits for the ALL-Link Cleanup Status Report (`0x58`) for as long as
/// the modem keeps sending cleanup traffic (a member's acknowledgment or NAK, or an ALL-Link
/// Cleanup Failure Report), and gives up after ``quietPeriod`` with none, or at ``cap`` after the
/// modem accepted the command, whichever comes first. Once the status report comes it keeps
/// listening for ``grace`` for the cleanup acknowledgments, NAKs and failure reports behind it,
/// whether they come in the same read of bytes as the report or a later one.
///
/// A quiet period longer than the cap is clamped to it, and the values aren't checked here: only the
/// server's options validate them, with ``Modem``'s callers free to pass any.
///
/// The Insteon Developer's Guide gives the time for members that answer, and not for a member
/// that doesn't, which makes the modem retry its cleanup before it reports. So the standard
/// values are unverified, chosen from bench runs.
public struct AllLinkCleanupWait: Hashable, Sendable {

  /// How long to wait for the modem to accept the command.
  public var echo: Duration

  /// How long to wait for more cleanup traffic before giving up on the status report.
  public var quietPeriod: Duration

  /// The longest to wait for the status report after the modem accepted the command.
  public var cap: Duration

  /// How long to go on collecting cleanup acknowledgments, NAKs and failure reports after the
  /// status report, which a Hub was seen to send ahead of a member's acknowledgment. Each message
  /// heard counts but doesn't extend it. Not settable from the server's options: it is internal
  /// to the modem layer.
  public var grace: Duration

  /// How long ``grace`` is unless a caller says: 500 milliseconds, unverified (one bench trace,
  /// REQ-7).
  public static let standardGrace: Duration = .milliseconds(500)

  /// The standard wait: 5 seconds for the echo, a quiet period of 15 seconds, a cap of 60
  /// seconds and a grace of 500 milliseconds. All four are unverified.
  public static let standard: AllLinkCleanupWait = AllLinkCleanupWait(echo: .seconds(5), quietPeriod: .seconds(15), cap: .seconds(60))

  /// Creates a wait.
  ///
  /// - Parameters:
  ///   - echo: How long to wait for the modem to accept the command.
  ///   - quietPeriod: How long to wait for more cleanup traffic.
  ///   - cap: The longest to wait for the status report.
  ///   - grace: How long to go on collecting cleanup messages after the status report.
  public init(echo: Duration, quietPeriod: Duration, cap: Duration, grace: Duration = AllLinkCleanupWait.standardGrace) {

    self.echo = echo
    self.quietPeriod = quietPeriod
    self.cap = cap
    self.grace = grace

  }

}
