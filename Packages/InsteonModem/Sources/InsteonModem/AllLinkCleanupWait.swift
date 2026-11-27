/// How long ``Modem/sendAllLinkCommand(group:command:wait:)`` waits.
///
/// The wait has three parts. After sending the command it waits up to ``echo`` for the modem to
/// accept it. After that it waits for the ALL-Link Cleanup Status Report (`0x58`) for as long as
/// the modem keeps sending cleanup traffic (a member's acknowledgment or NAK, or an ALL-Link
/// Cleanup Failure Report), and gives up after ``quietPeriod`` with none, or at ``cap`` after the
/// modem accepted the command, whichever comes first.
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

  /// The standard wait: 5 seconds for the echo, a quiet period of 15 seconds and a cap of 60
  /// seconds. All three are unverified.
  public static let standard: AllLinkCleanupWait = AllLinkCleanupWait(echo: .seconds(5), quietPeriod: .seconds(15), cap: .seconds(60))

  /// Creates a wait.
  ///
  /// - Parameters:
  ///   - echo: How long to wait for the modem to accept the command.
  ///   - quietPeriod: How long to wait for more cleanup traffic.
  ///   - cap: The longest to wait for the status report.
  public init(echo: Duration, quietPeriod: Duration, cap: Duration) {

    self.echo = echo
    self.quietPeriod = quietPeriod
    self.cap = cap

  }

}
