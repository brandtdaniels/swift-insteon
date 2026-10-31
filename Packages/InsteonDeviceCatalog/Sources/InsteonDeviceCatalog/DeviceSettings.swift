import InsteonProtocol

/// The heading a settings page shows a flag, reading or value under. Pages show the sections
/// in the order of `allCases`, which is the catalog's.
public enum SettingSection: String, Hashable, Sendable, CaseIterable, Comparable {

  /// The load the device switches or dims.
  case load = "Load"

  /// A relay.
  case relay = "Relay"

  /// A sensor or input.
  case sensor = "Sensor"

  /// The device's buttons.
  case buttons = "Buttons"

  /// The status LEDs and backlights.
  case leds = "LEDs"

  /// Night mode.
  case night = "Night"

  /// Timers.
  case timer = "Timer"

  /// Alarms.
  case alarm = "Alarm"

  /// A display.
  case display = "Display"

  /// The battery.
  case battery = "Battery"

  /// Linking and programming.
  case linking = "Linking"

  /// How the device communicates.
  case communication = "Communication"

  /// X10.
  case x10 = "X10"

  /// Counters and measurements for finding faults.
  case diagnostics = "Diagnostics"

  /// The section's place among the others, from 0.
  public var order: Int {

    Self.allCases.firstIndex(of: self) ?? 0

  }

  /// Whether a section comes before another on a settings page.
  ///
  /// - Parameters:
  ///   - lhs: A section.
  ///   - rhs: Another section.
  /// - Returns: Whether `lhs` comes first.
  public static func < (lhs: SettingSection, rhs: SettingSection) -> Bool {

    lhs.order < rhs.order

  }

}

/// One flag, reading or value a settings page shows, with what to call it and where.
///
/// ```swift
/// for item in commands.settingItems where !item.isAdvanced {
///   print(item.section?.rawValue ?? "Other", item.label, commands.isWritable(item))
/// }
/// ```
public struct SettingItem: Hashable, Sendable {

  /// Where the item's value comes from.
  public enum Source: Hashable, Sendable {

    /// A bit of a Get Operating Flags reply.
    case flag(OperatingFlag)

    /// A whole Get Operating Flags reply.
    case reading(OperatingReading)

    /// A byte of an extended Get's reply.
    case value(SettingValue)

  }

  /// Where the item's value comes from.
  public var source: Source

  /// The item's name in the command set, such as `"rampRate"`.
  public var name: SettingName

  /// What a settings page calls the item: the command set's label, or else its name.
  public var label: String

  /// The heading to show the item under, or `nil` if the command set doesn't say.
  public var section: SettingSection?

  /// Whether a settings page keeps the item out of sight unless asked.
  public var isAdvanced: Bool

  /// What the item is.
  public var summary: String

  /// Creates the item for an operating flag.
  ///
  /// - Parameter flag: The flag.
  public init(flag: OperatingFlag) {

    source = .flag(flag)
    name = flag.name
    label = flag.label ?? flag.name.rawValue
    section = flag.section
    isAdvanced = flag.isAdvanced
    summary = flag.summary

  }

  /// Creates the item for a reading.
  ///
  /// - Parameter reading: The reading.
  public init(reading: OperatingReading) {

    source = .reading(reading)
    name = reading.name
    label = reading.label ?? reading.name.rawValue
    section = reading.section
    isAdvanced = reading.isAdvanced
    summary = reading.summary

  }

  /// Creates the item for an extended settings value.
  ///
  /// - Parameter value: The value.
  public init(value: SettingValue) {

    source = .value(value)
    name = value.name
    label = value.label ?? value.name.rawValue
    section = value.section
    isAdvanced = value.isAdvanced
    summary = value.summary

  }

}

/// How an operating flag is changed.
public enum FlagChange: Hashable, Sendable {

  /// Set Operating Flags with this cmd2.
  case setOperatingFlags(UInt8)

  /// A standard command of the command set, such as night mode on.
  case standardCommand(DeviceStandardCommand)

}

/// How an extended settings value is changed.
public enum ValueChange: Hashable, Sendable {

  /// An extended Set.
  case extendedSet(SettingWrite)

  /// An extended command the value names in ``SettingValue/write``.
  case extendedCommand(DeviceExtendedCommand)

  /// The message that sets the value.
  ///
  /// An extended Set fills its other bytes from `current`, so they keep their values; read
  /// them first with an extended Get. Both are sent with the command's integrity bytes: a
  /// checksum in D14 for an extended Set, which i2CS devices require and others ignore.
  ///
  /// - Parameters:
  ///   - device: The device to send it to.
  ///   - button: The button or group, for a value that's per button. Ignored otherwise.
  ///   - name: The value's name.
  ///   - raw: The value's new byte.
  ///   - current: The values the device reported, by name.
  /// - Returns: The message.
  /// - Throws: ``SettingWriteError/missingValue(_:)`` if an extended Set has a byte whose
  ///   value isn't in `current`, or ``FieldError`` if the extended command has no parameter for
  ///   the value or the byte doesn't fit it.
  public func message(
    to device: InsteonAddress,
    button: UInt8 = 0x01,
    setting name: SettingName,
    to raw: UInt8,
    current: [SettingName: UInt8] = [:]
  ) throws -> ExtendedMessage {

    switch self {
    case let .extendedSet(write):
      var values: [SettingName: UInt8] = current
      values[name] = raw

      let userData: UserData = try write.userData(button: button, values: values)

      return ExtendedMessage(to: device, command: ExtendedDirectCommand.getSet(), userData: userData)
    case let .extendedCommand(command):
      // The parameter is the value's, or else the command's only one.
      let named: MessageField? = command.parameters.first { $0.name == name }
      let only: MessageField? = command.parameters.count == 1 ? command.parameters.first : nil

      guard let parameter = named ?? only else {

        throw FieldError.missingValue(name)

      }

      let values: [SettingName: FieldValue] = [parameter.name: .unnamed(Int(raw))]

      return try command.message(to: device, button: button, values: values)
    }

  }

}

/// Why text couldn't be read as a setting's value.
public enum SettingInputError: Error, Hashable, Sendable {

  /// The text isn't a value the setting takes. The associated values are the setting's name
  /// and the text.
  case unreadable(SettingName, String)

  /// The value is outside the setting's range, or doesn't fit a byte. The associated value is
  /// the setting's name.
  case outOfRange(SettingName)

}

extension ExtendedSettings {

  /// Whether a value is per button or group: whether the write that sets it is.
  ///
  /// - Parameter name: The value's name.
  /// - Returns: Whether the value is per button, `false` if no write sets it.
  public func isValuePerButton(_ name: SettingName) -> Bool {

    write(setting: name)?.isPerButton ?? false

  }

}

extension OperatingFlag {

  /// Reads the state someone gave for a flag.
  ///
  /// - Parameter text: `on`, `true`, `yes` or `1` for set, and `off`, `false`, `no` or `0`
  ///   for clear, in any case.
  /// - Returns: The state, or `nil` if the text isn't one of them.
  public static func state(parsing text: String) -> Bool? {

    switch text.lowercased() {
    case "on", "true", "yes", "1":
      true
    case "off", "false", "no", "0":
      false
    default:
      nil
    }

  }

}

extension FieldUnit {

  /// The unit as a settings page writes it after a number, such as `"%"` or `" s"`.
  public var symbol: String {

    switch self {
    case .percent: "%"
    case .celsius: " °C"
    case .fahrenheit: " °F"
    case .displayDegrees: "°"
    case .seconds: " s"
    case .minutes: " min"
    case .hours: " h"
    }

  }

  /// The suffixes someone can type after a number in the unit, lowercased and without spaces.
  var suffixes: [String] {

    switch self {
    case .percent: ["%"]
    case .celsius: ["°c", "c"]
    case .fahrenheit: ["°f", "f"]
    case .displayDegrees: ["°", "°c", "°f", "c", "f"]
    case .seconds: ["s", "sec", "second", "seconds"]
    case .minutes: ["min", "minute", "minutes"]
    case .hours: ["h", "hr", "hour", "hours"]
    }

  }

}

extension CommandSet {

  /// The flags, readings and extended settings values a settings page shows, in the order of
  /// their sections and, within a section, the command set's order. Items without a section
  /// come last.
  public var settingItems: [SettingItem] {

    var items: [SettingItem] = operatingFlags.map(SettingItem.init(flag:))
    items += readings.map(SettingItem.init(reading:))
    items += (extendedSettings?.values ?? []).map(SettingItem.init(value:))

    let numbered: [(offset: Int, element: SettingItem)] = Array(items.enumerated())
    let sorted: [(offset: Int, element: SettingItem)] = numbered.sorted { lhs, rhs in

      let left: Int = lhs.element.section?.order ?? Int.max
      let right: Int = rhs.element.section?.order ?? Int.max

      return left == right ? lhs.offset < rhs.offset : left < right

    }

    return sorted.map(\.element)

  }

  /// The item someone named, by its name or its label, in any case.
  ///
  /// - Parameter text: The name, such as `"rampRate"`, or label, such as `"ramp rate"`.
  /// - Returns: The item whose name matches exactly, or else the first whose name or label
  ///   matches in any case, or `nil` if there's none.
  public func settingItem(named text: String) -> SettingItem? {

    let items: [SettingItem] = settingItems

    if let exact = items.first(where: { $0.name.rawValue == text }) {

      return exact

    }

    let lowercased: String = text.lowercased()

    return items.first { $0.name.rawValue.lowercased() == lowercased || $0.label.lowercased() == lowercased }

  }

  /// How to set or clear an operating flag.
  ///
  /// - Parameters:
  ///   - flag: The flag.
  ///   - value: The state to give it.
  /// - Returns: Set Operating Flags with the flag's ``OperatingFlag/on`` or
  ///   ``OperatingFlag/off``, or else the standard command it names in
  ///   ``OperatingFlag/onCommand`` or ``OperatingFlag/offCommand``, or `nil` if the command
  ///   set gives no way.
  public func change(for flag: OperatingFlag, setting value: Bool) -> FlagChange? {

    if let command2 = value ? flag.on : flag.off {

      return .setOperatingFlags(command2)

    }

    guard let name = value ? flag.onCommand : flag.offCommand, let command = standardCommand(named: name) else {

      return nil

    }

    return .standardCommand(command)

  }

  /// How to set an extended settings value.
  ///
  /// - Parameter value: The value.
  /// - Returns: The extended Set with a byte for it, or else the extended command it names in
  ///   ``SettingValue/write``, or `nil` if the command set gives no way.
  public func change(for value: SettingValue) -> ValueChange? {

    if let write = extendedSettings?.write(setting: value.name) {

      return .extendedSet(write)

    }

    guard let name = value.write, let command = extendedCommand(named: name) else {

      return nil

    }

    return .extendedCommand(command)

  }

  /// Whether the command set gives a way to change an item: a flag that can be set or
  /// cleared, or a value with a write. Readings are read-only.
  ///
  /// - Parameter item: The item.
  /// - Returns: Whether it can be changed.
  public func isWritable(_ item: SettingItem) -> Bool {

    switch item.source {
    case let .flag(flag):
      change(for: flag, setting: true) != nil || change(for: flag, setting: false) != nil
    case .reading:
      false
    case let .value(value):
      change(for: value) != nil
    }

  }

  /// A value as a settings page shows it: its value table's label, its buttons, a number in
  /// its unit, a number for a value with a range, or else the byte in hexadecimal.
  ///
  /// - Parameters:
  ///   - value: The value.
  ///   - raw: The byte the device reported.
  /// - Returns: The text, such as `"0.5 s"`, `"50%"`, `"buttons 1, 3"` or `"0x20"`.
  public func text(for value: SettingValue, raw: UInt8) -> String {

    if let name = value.table, let entry = valueTable(named: name)?.entry(for: raw) {

      return entry.label

    }

    if value.kind == .buttons {

      let buttons: [String] = (0..<8).filter { (bit: Int) -> Bool in raw >> bit & 1 == 1 }.map { (bit: Int) -> String in String(bit + 1) }

      return buttons.isEmpty ? "no buttons" : "buttons " + buttons.joined(separator: ", ")

    }

    if value.unit != nil || value.scale != 1 {

      let number: Double = Double(raw) * value.scale

      return Self.numberText(number, unit: value.unit) + (value.unit?.symbol ?? "")

    }

    if value.range != nil {

      return String(raw)

    }

    return "0x" + raw.hexDigits

  }

  /// Reads the text someone gave for a value as the byte to write.
  ///
  /// The text can be a byte in hexadecimal, such as `0x1C`; a label of the value's table, such
  /// as `0.5 s`, or a duration the table has; buttons such as `1,3`, or `none`; or a number,
  /// in the value's unit, with or without the unit, such as `50%` or `50`. Case and spaces
  /// don't matter. A byte or number outside the value's range is refused.
  ///
  /// - Parameters:
  ///   - value: The value.
  ///   - text: The text.
  /// - Returns: The byte.
  /// - Throws: ``SettingInputError/unreadable(_:_:)`` if the text isn't one of these, or
  ///   ``SettingInputError/outOfRange(_:)`` if it's outside the value's range.
  public func raw(for value: SettingValue, parsing text: String) throws(SettingInputError) -> UInt8 {

    let compact: String = String(text.lowercased().filter { !$0.isWhitespace })
    let unreadable = SettingInputError.unreadable(value.name, text)

    if compact.hasPrefix("0x") {

      guard compact.count <= 4, let byte = UInt8(compact.dropFirst(2), radix: 16) else {

        throw unreadable

      }

      return try Self.checked(byte, in: value)

    }

    let table: ValueTable? = value.table.flatMap { valueTable(named: $0) }

    let labeled: ValueTable.Entry? = table?.entries.first { (entry: ValueTable.Entry) -> Bool in

      String(entry.label.lowercased().filter { !$0.isWhitespace }) == compact

    }

    if let entry = labeled {

      return entry.value

    }

    if value.kind == .buttons {

      return try Self.buttonMask(compact, value: value, text: text)

    }

    guard let parsed = Self.number(in: compact) else {

      throw unreadable

    }

    let number: Double = parsed.number
    let suffix: String = parsed.suffix

    if let table {

      return try Self.entry(in: table, number: number, suffix: suffix, value: value, text: text)

    }

    if !suffix.isEmpty {

      guard let unit = value.unit, unit.suffixes.contains(suffix) else {

        throw unreadable

      }

    }

    let counts: Double = (number / value.scale).rounded()

    guard counts >= 0, counts <= 255 else {

      throw .outOfRange(value.name)

    }

    return try Self.checked(UInt8(counts), in: value)

  }

  // MARK: - Reading text

  /// A number with one decimal place at most, or none for a percentage.
  static func numberText(_ number: Double, unit: FieldUnit?) -> String {

    let factor: Double = unit == .percent ? 1 : 10
    let rounded: Double = (number * factor).rounded() / factor

    if rounded == rounded.rounded(), abs(rounded) < 1_000_000 {

      return String(Int(rounded))

    }

    return String(rounded)

  }

  /// The number at the start of text and the suffix after it, or `nil` if it doesn't start
  /// with one.
  private static func number(in compact: String) -> (number: Double, suffix: String)? {

    let end: String.Index = compact.firstIndex { (character: Character) -> Bool in

      !(character.isASCII && (character.isNumber || character == "." || character == "-"))

    } ?? compact.endIndex

    guard let number = Double(compact[..<end]) else {

      return nil

    }

    return (number, String(compact[end...]))

  }

  /// A byte, if it's in the value's range.
  private static func checked(_ byte: UInt8, in value: SettingValue) throws(SettingInputError) -> UInt8 {

    if let range = value.range, !range.contains(byte) {

      throw .outOfRange(value.name)

    }

    return byte

  }

  /// The mask for buttons such as `1,3`, or `none`, if it's in the value's range.
  ///
  /// - Parameters:
  ///   - compact: The text, lowercased and without spaces.
  ///   - value: The value.
  ///   - text: The text as it was given, for the error.
  private static func buttonMask(_ compact: String, value: SettingValue, text: String) throws(SettingInputError) -> UInt8 {

    if compact == "none" {

      return try Self.checked(0, in: value)

    }

    var mask: UInt8 = 0

    // Empty parts, as in "1,,3" or "1,", are refused rather than skipped.
    for part in compact.split(separator: ",", omittingEmptySubsequences: false) {

      guard let button = Int(part) else {

        throw .unreadable(value.name, text)

      }

      guard (1...8).contains(button) else {

        throw .outOfRange(value.name)

      }

      mask |= UInt8(1) << (button - 1)

    }

    return try Self.checked(mask, in: value)

  }

  /// The table entry whose duration is a number of seconds, minutes or hours.
  private static func entry(in table: ValueTable, number: Double, suffix: String, value: SettingValue, text: String) throws(SettingInputError) -> UInt8 {

    var seconds: Double = number

    if FieldUnit.minutes.suffixes.contains(suffix) {

      seconds = number * 60

    } else if FieldUnit.hours.suffixes.contains(suffix) {

      seconds = number * 3_600

    } else if !FieldUnit.seconds.suffixes.contains(suffix) {

      throw .unreadable(value.name, text)

    }

    // Compared in floating point, so no text, however long, overflows: a duration no table
    // has, NaN or an infinity matches no entry.
    let milliseconds: Double = (seconds * 1_000).rounded()

    guard milliseconds.isFinite else {

      throw .outOfRange(value.name)

    }

    for entry in table.entries {

      guard let duration = entry.duration else {

        continue

      }

      let components = duration.components
      let entryMilliseconds: Double = Double(components.seconds) * 1_000 + (Double(components.attoseconds) / 1e15).rounded(.towardZero)

      if abs(entryMilliseconds - milliseconds) <= 1 {

        return entry.value

      }

    }

    throw .outOfRange(value.name)

  }

}
