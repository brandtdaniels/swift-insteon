/// How ``Modem`` and ``PowerLincController`` wait for and retry commands.
///
/// A device answers each command before it takes the next: a modem echoes it, and a PowerLinc
/// Controller echoes it or returns the data it asks for. A device that's busy rejects the
/// command with a NAK, so it's sent again after a delay.
public struct RetryPolicy: Hashable, Sendable {

  /// How many times to send a command before giving up. At least 1; a smaller value is
  /// raised to 1.
  public var attempts: Int {

    didSet { attempts = max(1, attempts) }

  }

  /// How long to wait before sending a rejected command again, or asking a device again for an
  /// ALL-Link record that didn't arrive.
  public var delay: Duration

  /// How long to wait for the device to answer a command.
  public var answerTimeout: Duration

  /// Creates a retry policy.
  ///
  /// - Parameters:
  ///   - attempts: How many times to send a command before giving up. Defaults to 3, and a
  ///     value below 1 is raised to 1.
  ///   - delay: How long to wait before resending a rejected command or asking again for a
  ///     record. Defaults to half a second, which gives a busy device time to finish.
  ///   - answerTimeout: How long to wait for an answer. Defaults to 2 seconds.
  public init(attempts: Int = 3, delay: Duration = .milliseconds(500), answerTimeout: Duration = .seconds(2)) {

    self.attempts = max(1, attempts)
    self.delay = delay
    self.answerTimeout = answerTimeout

  }

}
