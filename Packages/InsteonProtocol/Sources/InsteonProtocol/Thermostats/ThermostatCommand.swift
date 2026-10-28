/// Commands a thermostat accepts in a standard direct message, from Insteon's thermostat
/// command tables, SmartLabs' Thermostat Adapter (Venstar/Totaline) datasheet and the TempLinc
/// Thermostat (2441TH) product requirements.
///
/// Thermostats don't all accept every command, or give every value the same meaning, so check
/// the notes on each against the thermostat's model.
///
/// Temperatures and setpoints are ``ThermostatTemperature`` values, in half degrees of the
/// scale the thermostat displays. A read returns its value in cmd2 of the acknowledgement:
///
/// ```swift
/// let ack = try await modem.request(StandardMessage(to: thermostat, command: ThermostatCommand.readZone(.temperature)))
/// let temperature = ThermostatTemperature(rawValue: ack.command.command2)
///
/// try await modem.request(StandardMessage(to: thermostat, command: ThermostatCommand.setHeatSetpoint(ThermostatTemperature(degrees: 68)!)))
/// ```
///
/// A thermostat can be set to accept the commands that change it only in an extended message.
/// Send those in an ``ExtendedMessage`` whose user data is
/// ``ThermostatCommand/protectedUserData``.
public enum ThermostatCommand: Hashable, Sendable {

  /// Raises the setpoint by a number of half degrees (cmd1 `0x68`).
  case raiseSetpoint(halfDegrees: UInt8)

  /// Lowers the setpoint by a number of half degrees (cmd1 `0x69`).
  case lowerSetpoint(halfDegrees: UInt8)

  /// Reads one of a zone's values, in the acknowledgement's cmd2 (cmd1 `0x6A`).
  ///
  /// cmd2 holds the zone in bits 0 to 4 and the value to read in bits 5 and 6, so the main
  /// zone's temperature is `0x00`, its setpoint `0x20` and its humidity `0x60`.
  case readZone(ThermostatReading, zone: ThermostatZone = .main)

  /// Reads the mode, as a ``ThermostatMode`` in the acknowledgement's cmd2 (cmd1 `0x6B`,
  /// cmd2 `0x02`). The TempLinc engineering specification gives it with these values, but the
  /// final TempLinc product requirements drop it; a TempLinc reports its mode in a
  /// ``ThermostatStatusReport`` instead.
  case readMode

  /// Sets the mode (cmd1 `0x6B`).
  case setMode(ThermostatModeSetting)

  /// Sets whether the fan runs all the time or only while heating or cooling (cmd1 `0x6B`,
  /// cmd2 `0x07` or `0x08`).
  case setFan(ThermostatFanSetting)

  /// Sets the cool setpoint (cmd1 `0x6C`).
  case setCoolSetpoint(ThermostatTemperature)

  /// Sets the heat setpoint (cmd1 `0x6D`).
  case setHeatSetpoint(ThermostatTemperature)

  /// The user data that sends the command in an extended message to a thermostat that accepts
  /// only extended commands: cmd1 and cmd2 again in D1 and D2, and zeros after.
  public var protectedUserData: UserData {

    var userData = UserData()
    userData[1] = command.command1
    userData[2] = command.command2

    return userData

  }

}

/// A mode to set a thermostat to with ``ThermostatCommand/setMode(_:)``.
public enum ThermostatModeSetting: UInt8, Hashable, Sendable, CaseIterable {

  /// Heat to the heat setpoint (cmd2 `0x04`).
  case heat = 0x04

  /// Cool to the cool setpoint (cmd2 `0x05`).
  case cool = 0x05

  /// Heat or cool, whichever the temperature needs (cmd2 `0x06`). A TempLinc calls this
  /// manual auto: at the setpoints set by hand.
  case auto = 0x06

  /// Turn heating and cooling off (cmd2 `0x09`).
  case off = 0x09

  /// Heat, following the thermostat's program (cmd2 `0x0A`). A TempLinc instead takes
  /// `0x0A` as its programmed auto mode: heat or cool, following its program.
  case programHeat = 0x0A

  /// Cool, following the thermostat's program (cmd2 `0x0B`). A TempLinc doesn't accept it.
  case programCool = 0x0B

  /// Heat or cool, following the thermostat's program (cmd2 `0x0C`). A TempLinc doesn't accept
  /// it; use ``ThermostatModeSetting/programHeat``, its `0x0A`.
  case programAuto = 0x0C

}

/// How a thermostat's fan runs, set with ``ThermostatCommand/setFan(_:)``.
public enum ThermostatFanSetting: UInt8, Hashable, Sendable, CaseIterable {

  /// The fan runs all the time (cmd2 `0x07`).
  case on = 0x07

  /// The fan runs only while heating or cooling (cmd2 `0x08`).
  case auto = 0x08

}

// MARK: - StandardCommandConvertible

extension ThermostatCommand: StandardCommandConvertible {

  /// The command's cmd1 and cmd2 bytes.
  public var command: Command {

    switch self {
    case let .raiseSetpoint(halfDegrees):
      Command(command1: 0x68, command2: halfDegrees)
    case let .lowerSetpoint(halfDegrees):
      Command(command1: 0x69, command2: halfDegrees)
    case let .readZone(reading, zone):
      Command(command1: 0x6A, command2: reading.rawValue << 5 | zone.rawValue)
    case .readMode:
      Command(command1: 0x6B, command2: 0x02)
    case let .setMode(mode):
      Command(command1: 0x6B, command2: mode.rawValue)
    case let .setFan(fan):
      Command(command1: 0x6B, command2: fan.rawValue)
    case let .setCoolSetpoint(setpoint):
      Command(command1: 0x6C, command2: setpoint.rawValue)
    case let .setHeatSetpoint(setpoint):
      Command(command1: 0x6D, command2: setpoint.rawValue)
    }

  }

}
