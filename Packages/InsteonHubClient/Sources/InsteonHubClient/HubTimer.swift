import InsteonProtocol

/// A time of day a 2242 Hub's timer fires at, to the minute.
public struct HubClockTime: Hashable, Sendable {

  /// The hour, from 0 through 23.
  public let hour: Int

  /// The minute, from 0 through 59.
  public let minute: Int

  /// Creates a time of day.
  ///
  /// - Parameters:
  ///   - hour: The hour, from 0 through 23.
  ///   - minute: The minute, from 0 through 59.
  /// - Returns: `nil` unless both are in range.
  public init?(hour: Int, minute: Int) {

    guard (0...23).contains(hour), (0...59).contains(minute) else {

      return nil

    }

    self.hour = hour
    self.minute = minute

  }

  /// The time as `HH:MM`, as the Hub's clock takes it.
  var clockText: String {

    Self.twoDigits(hour) + ":" + Self.twoDigits(minute)

  }

  /// The time as a timer's field. The Hub reads `00:00` there as no time, so midnight is
  /// written `24:00`, as Insteon's Hub app writes it.
  var timerText: String {

    hour == 0 && minute == 0 ? "24:00" : clockText

  }

  private static func twoDigits(_ value: Int) -> String {

    value < 10 ? "0\(value)" : "\(value)"

  }

}

/// When a 2242 Hub's timer turns its slot on or off.
public enum HubTimerTime: Hashable, Sendable {

  /// At a time of day.
  case clock(HubClockTime)

  /// At sunrise, from the Hub's table of sunrise times by month.
  case sunrise

  /// At sunset, from the Hub's table of sunset times by month.
  case sunset

}

/// A day of the week, as a 2242 Hub's timers and clock name them.
public enum HubWeekday: Int, Hashable, Sendable, CaseIterable {

  /// Monday.
  case monday

  /// Tuesday.
  case tuesday

  /// Wednesday.
  case wednesday

  /// Thursday.
  case thursday

  /// Friday.
  case friday

  /// Saturday.
  case saturday

  /// Sunday.
  case sunday

}

/// The days of the week a 2242 Hub's timer runs on.
public struct HubWeekdays: OptionSet, Hashable, Sendable {

  /// Every day of the week.
  public static let everyDay = HubWeekdays(HubWeekday.allCases)

  /// The days, one bit per ``HubWeekday`` in order, Monday first.
  public let rawValue: UInt8

  /// Creates days from their bits.
  ///
  /// - Parameter rawValue: One bit per ``HubWeekday``, Monday in bit 0.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue & 0x7F

  }

  /// Creates days from a list.
  ///
  /// - Parameter days: The days.
  public init(_ days: some Sequence<HubWeekday>) {

    self.init(rawValue: days.reduce(0) { $0 | 1 << $1.rawValue })

  }

  /// Whether the days include a day.
  ///
  /// - Parameter day: The day.
  /// - Returns: `true` if the day is included.
  public func contains(_ day: HubWeekday) -> Bool {

    contains(HubWeekdays([day]))

  }

}

/// A name a 2242 Hub shows for a slot.
///
/// The Hub's requests separate their fields with `=`, so a name is limited to ASCII letters and
/// digits. Insteon's Hub app removed the spaces from its names before writing them.
public struct HubSlotName: RawRepresentable, Hashable, Sendable {

  /// The name.
  public let rawValue: String

  /// Creates a name.
  ///
  /// - Parameter rawValue: The name.
  /// - Returns: `nil` unless the name is ASCII letters and digits, and not empty.
  public init?(rawValue: String) {

    guard !rawValue.isEmpty, rawValue.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {

      return nil

    }

    self.rawValue = rawValue

  }

}

/// A timer a 2242 Hub runs for one of its slots: the times it turns the slot on and off, and
/// the days it does so.
///
/// The Hub sends the slot's on and off commands, which ``Hub/setCommands(_:for:)`` sets. A
/// timer with no times and no days runs never, which is how Insteon's Hub app removed a timer.
public struct HubTimer: Hashable, Sendable {

  /// The name the Hub shows for the slot.
  public var name: HubSlotName

  /// When the slot turns on, or `nil` for never.
  public var on: HubTimerTime?

  /// When the slot turns off, or `nil` for never.
  public var off: HubTimerTime?

  /// The days the timer runs.
  public var days: HubWeekdays

  /// Creates a timer.
  ///
  /// - Parameters:
  ///   - name: The name the Hub shows for the slot.
  ///   - on: When the slot turns on, or `nil` for never.
  ///   - off: When the slot turns off, or `nil` for never.
  ///   - days: The days the timer runs.
  public init(name: HubSlotName, on: HubTimerTime?, off: HubTimerTime?, days: HubWeekdays) {

    self.name = name
    self.on = on
    self.off = off
    self.days = days

  }

}

/// The commands a 2242 Hub sends when a slot's timer turns it on and off.
///
/// Each is a serial command for the Hub's modem, such as sending a device a standard message or
/// sending an ALL-Link group command.
public struct HubSlotCommands: Hashable, Sendable {

  /// The command that turns the slot on.
  public var on: SerialCommand

  /// The command that turns the slot off.
  public var off: SerialCommand

  /// Creates a slot's commands.
  ///
  /// - Parameters:
  ///   - on: The command that turns the slot on.
  ///   - off: The command that turns the slot off.
  public init(on: SerialCommand, off: SerialCommand) {

    self.on = on
    self.off = off

  }

}
