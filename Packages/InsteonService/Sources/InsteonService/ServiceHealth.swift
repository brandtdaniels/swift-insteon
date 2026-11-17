import Foundation

/// What the service can say about itself without asking hardware anything.
public struct ServiceHealth: Equatable, Sendable {
  /// How ready the service is to control devices.
  public enum Readiness: Equatable, Sendable {
    /// No connection has succeeded since the service started. Cached devices are served.
    case starting
    /// The modem is connected.
    case ready
    /// The modem was connected earlier in this run and isn't connected. Cached devices are
    /// served and the service keeps reconnecting.
    case degraded
  }

  /// How ready the service is.
  public let readiness: Readiness
  /// Whether the modem is connected, and if not, why.
  public let modem: ModemConnectionState
  /// When the modem last answered the service or sent it something, or `nil` if it never has
  /// since the service started.
  public let lastHardwareExchange: Date?
  /// When the cached device information was last confirmed against the modem's ALL-Link
  /// database. Until the first connection it is when the saved snapshot was written, or `nil`
  /// if there is none.
  public let deviceInformationUpdated: Date?
  /// The outcome of the latest snapshot save.
  public let persistence: PersistenceOutcome
  /// When this report was made.
  public let checkedAt: Date

  /// Creates a report.
  public init(readiness: Readiness, modem: ModemConnectionState, lastHardwareExchange: Date?, deviceInformationUpdated: Date?, persistence: PersistenceOutcome, checkedAt: Date) {
    self.readiness = readiness
    self.modem = modem
    self.lastHardwareExchange = lastHardwareExchange
    self.deviceInformationUpdated = deviceInformationUpdated
    self.persistence = persistence
    self.checkedAt = checkedAt
  }
}
