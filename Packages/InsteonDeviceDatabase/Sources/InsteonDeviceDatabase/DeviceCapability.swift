import InsteonProtocol

/// Something a product can do, as its device profile describes it.
public enum DeviceCapability: Hashable, Sendable {

  /// Which mode values a thermostat uses in its mode status reports.
  public enum ThermostatModeValues: String, Hashable, Sendable, Decodable {

    /// The values in Insteon's thermostat command tables, which `ThermostatMode` reads.
    case commandTable

    /// A TempLinc's own values, which `TempLincMode` reads.
    case tempLinc

  }

  /// What a product means by a command it sends to one of its groups.
  public struct GroupEvent: Hashable, Sendable {

    /// The group the command is sent to.
    public var group: AllLinkGroupNumber

    /// The command's cmd1, such as `0x11` for on.
    public var command1: UInt8

    /// What the command means.
    public var event: DeviceEventName

    /// Creates a group event.
    ///
    /// - Parameters:
    ///   - group: The group the command is sent to.
    ///   - command1: The command's cmd1.
    ///   - event: What the command means.
    public init(group: AllLinkGroupNumber, command1: UInt8, event: DeviceEventName) {

      self.group = group
      self.command1 = command1
      self.event = event

    }

  }

  /// Turns a load on and off.
  case onOff

  /// Dims a load.
  case dimmable

  /// A modem: a PowerLinc Modem, USB Adapter or Hub's own modem.
  case modem

  /// A Hub's local HTTP interface on a port, through which its modem is driven.
  case hub(port: UInt16)

  /// The Hub Pro's own HTTP interface on a port, for adding and removing devices and updating
  /// its software.
  case hubPro(port: UInt16)

  /// A thermostat, with the mode values it reports and whether it measures humidity.
  case thermostat(modeValues: ThermostatModeValues, measuresHumidity: Bool)

  /// What the product means by the commands it sends to its groups.
  case groupEvents([GroupEvent])

  /// A heartbeat the product sends to a group at an interval, for noticing a product that
  /// has gone quiet.
  case heartbeat(group: AllLinkGroupNumber, interval: Duration)

}

extension DeviceCapability {

  /// The capability kinds this package reads. A profile's capability of any other kind, from
  /// a later version of the database, is skipped.
  static let kinds: Set<String> = ["onOff", "dimmable", "modem", "hub", "hubPro", "thermostat", "groupEvents", "heartbeat"]

  private enum CodingKeys: String, CodingKey {

    case kind
    case port
    case modeValues
    case humidity
    case events
    case group
    case intervalMinutes

  }

  private struct Event: Decodable {

    let group: ProfileByte

    let command1: ProfileByte

    let event: String

  }

  /// Decodes a capability of a kind in ``kinds``.
  init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)

    switch try container.decode(String.self, forKey: .kind) {
    case "onOff":
      self = .onOff
    case "dimmable":
      self = .dimmable
    case "modem":
      self = .modem
    case "hub":
      self = .hub(port: try container.decode(UInt16.self, forKey: .port))
    case "hubPro":
      self = .hubPro(port: try container.decode(UInt16.self, forKey: .port))
    case "thermostat":
      self = .thermostat(
        modeValues: try container.decode(ThermostatModeValues.self, forKey: .modeValues),
        measuresHumidity: try container.decodeIfPresent(Bool.self, forKey: .humidity) ?? false
      )
    case "groupEvents":
      self = .groupEvents(try container.decode([Event].self, forKey: .events).map { event in

        GroupEvent(group: AllLinkGroupNumber(rawValue: event.group.value), command1: event.command1.value, event: DeviceEventName(rawValue: event.event))

      })
    case "heartbeat":
      let minutes = try container.decode(Int.self, forKey: .intervalMinutes)

      guard minutes > 0 else {

        throw DecodingError.dataCorruptedError(forKey: .intervalMinutes, in: container, debugDescription: "A heartbeat interval must be at least a minute.")

      }

      self = .heartbeat(group: AllLinkGroupNumber(rawValue: try container.decode(ProfileByte.self, forKey: .group).value), interval: .seconds(minutes * 60))
    case let kind:
      throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "\(kind) isn't a capability kind this package reads.")
    }

  }

}
