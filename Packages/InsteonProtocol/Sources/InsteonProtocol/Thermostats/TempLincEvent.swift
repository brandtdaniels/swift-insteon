/// What a TempLinc Thermostat (2441TH) or TempLinc Wireless Zone Thermostat (2441ZTH) reports
/// to its groups, as the TempLinc specification and product requirements give them.
///
/// Devices linked to a group follow it, such as an I/O Linc driving a dehumidifier from
/// group 3. In auto mode, a device linked to groups 1 and 2 gets both. Group `0xFE` carries
/// ``ThermostatStatusReport`` messages instead.
///
/// ```swift
/// if let event = TempLincEvent(command) {
///   print(command.controller, event)
/// }
/// ```
public enum TempLincEvent: Hashable, Sendable {

  /// Cooling started: on to group 1.
  case coolingStarted

  /// Cooling stopped: off to group 1.
  case coolingStopped

  /// Heating started: on to group 2.
  case heatingStarted

  /// Heating stopped: off to group 2.
  case heatingStopped

  /// The humidity rose above the high humidity setpoint: on to group 3.
  case dehumidifyingStarted

  /// The humidity fell back from the high humidity setpoint: off to group 3.
  case dehumidifyingStopped

  /// The humidity fell below the low humidity setpoint: on to group 4.
  case humidifyingStarted

  /// The humidity rose back from the low humidity setpoint: off to group 4.
  case humidifyingStopped

  /// Reads a TempLinc's event from a group command.
  ///
  /// - Parameter command: A command the TempLinc sent.
  /// - Returns: `nil` if the command isn't one of the events above.
  public init?(_ command: GroupCommand) {

    switch (command.group.rawValue, command.command1) {
    case (0x01, 0x11): self = .coolingStarted
    case (0x01, 0x13): self = .coolingStopped
    case (0x02, 0x11): self = .heatingStarted
    case (0x02, 0x13): self = .heatingStopped
    case (0x03, 0x11): self = .dehumidifyingStarted
    case (0x03, 0x13): self = .dehumidifyingStopped
    case (0x04, 0x11): self = .humidifyingStarted
    case (0x04, 0x13): self = .humidifyingStopped
    default: return nil
    }

  }

}
