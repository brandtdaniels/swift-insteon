/// How the service waits between attempts to reach its modem.
///
/// The delay doubles after each failed attempt up to a cap, and a random fraction is taken off
/// it so that several services behind one Hub don't retry together. Rejected credentials wait a
/// fixed, long time, since the same credentials fail the same way.
public struct ReconnectPolicy: Equatable, Sendable {
  /// The wait after the first failed attempt.
  public var initialDelay: Duration
  /// The longest wait between attempts for any cause but rejected credentials.
  public var maximumDelay: Duration
  /// The wait between attempts while the Hub rejects the credentials.
  public var credentialsDelay: Duration
  /// The largest fraction, from 0 through 1, taken off a delay at random.
  public var jitter: Double
  /// Whether the service tries again after a connection ends. When `false`, the first failure
  /// or end of the connection ends the service's run.
  public var reconnects: Bool

  /// Creates a policy.
  public init(initialDelay: Duration, maximumDelay: Duration, credentialsDelay: Duration, jitter: Double, reconnects: Bool) {
    self.initialDelay = initialDelay
    self.maximumDelay = maximumDelay
    self.credentialsDelay = credentialsDelay
    self.jitter = min(max(jitter, 0), 1)
    self.reconnects = reconnects
  }

  /// Waits 1 second, doubling to 60 seconds, with up to a quarter taken off, and waits
  /// 15 minutes between attempts with rejected credentials.
  public static let standard = ReconnectPolicy(initialDelay: .seconds(1), maximumDelay: .seconds(60), credentialsDelay: .seconds(900), jitter: 0.25, reconnects: true)

  /// Never tries again: the run ends with the first failure, as for a host that keeps the
  /// modem session open itself.
  public static let never = ReconnectPolicy(initialDelay: .zero, maximumDelay: .zero, credentialsDelay: .zero, jitter: 0, reconnects: false)

  /// The wait before the next attempt.
  ///
  /// - Parameters:
  ///   - failures: How many attempts in a row have failed, at least 1.
  ///   - cause: Why the last one failed.
  ///   - unit: A random number from 0 up to, not including, 1.
  func delay(afterFailures failures: Int, cause: ModemUnavailability, unit: Double) -> Duration {
    if cause == .credentialsRejected { return credentialsDelay }
    let doublings = min(max(failures - 1, 0), 30)
    let base = min(maximumDelay, initialDelay * Double(1 << doublings))
    return base * (1 - jitter * min(max(unit, 0), 1))
  }
}
