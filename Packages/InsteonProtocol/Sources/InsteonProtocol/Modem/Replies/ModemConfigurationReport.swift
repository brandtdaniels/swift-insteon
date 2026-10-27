/// The settings a modem reports in reply to ``SerialCommand/getModemConfiguration``.
///
/// The reply ends with two bytes after the configuration flags. Later firmware uses them for
/// ``applicationRetries`` and ``databaseDelta``; older firmware marks them as spare, so their
/// values have no meaning on those modems.
public struct ModemConfigurationReport: Hashable, Sendable {

  /// The modem's configuration flags.
  public var configuration: ModemConfiguration

  /// How many times the modem retries a direct message that isn't acknowledged, as set with
  /// ``SerialCommand/setApplicationRetries(_:)``.
  public var applicationRetries: UInt8

  /// A value that changes whenever the modem's ALL-Link database does.
  public var databaseDelta: UInt8

  /// Creates a configuration report.
  ///
  /// - Parameters:
  ///   - configuration: The modem's configuration flags.
  ///   - applicationRetries: The number of application retries.
  ///   - databaseDelta: The database delta.
  public init(configuration: ModemConfiguration, applicationRetries: UInt8, databaseDelta: UInt8) {

    self.configuration = configuration
    self.applicationRetries = applicationRetries
    self.databaseDelta = databaseDelta

  }

}
