/// A change a thermostat reports on its own.
///
/// A thermostat sends each of its report recipients a direct message whenever its
/// temperature, humidity, mode or setpoints change. A Venstar adapter reports to each device
/// linked to it while it was off. A TempLinc reports to each device linked to its group
/// `0xFE`, which only software can link, a few seconds after a change settles.
///
/// ```swift
/// if case let .messageReceived(message) = reply, let report = ThermostatStatusReport(message) {
///   print(message.sender, report)
/// }
/// ```
public enum ThermostatStatusReport: Hashable, Sendable {

  /// The temperature changed (cmd1 `0x6E`).
  case temperature(ThermostatTemperature)

  /// The relative humidity changed, in percent (cmd1 `0x6F`).
  case humidity(percent: UInt8)

  /// The mode changed (cmd1 `0x70`), in the thermostat's own values.
  case mode(ThermostatModeCode)

  /// The cool setpoint changed (cmd1 `0x71`).
  case coolSetpoint(ThermostatTemperature)

  /// The heat setpoint changed (cmd1 `0x72`).
  case heatSetpoint(ThermostatTemperature)

  /// Reads a status report from a received message.
  ///
  /// - Parameter message: A message the modem received.
  /// - Returns: `nil` unless the message is a standard direct message with one of the report
  ///   commands above.
  public init?(_ message: ReceivedMessage) {

    guard message.flags.messageType == .direct, !message.flags.isExtended else {

      return nil

    }

    let value = message.command.command2

    switch message.command.command1 {
    case 0x6E: self = .temperature(ThermostatTemperature(rawValue: value))
    case 0x6F: self = .humidity(percent: value)
    case 0x70: self = .mode(ThermostatModeCode(rawValue: value))
    case 0x71: self = .coolSetpoint(ThermostatTemperature(rawValue: value))
    case 0x72: self = .heatSetpoint(ThermostatTemperature(rawValue: value))
    default: return nil
    }

  }

}
