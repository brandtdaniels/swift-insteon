import InsteonDeviceCatalog
import InsteonProtocol

/// What a device reported to `insteon device ADDRESS settings`: the cmd2 of each Get Operating
/// Flags reply, and the values of each extended Get's reply.
public struct ReportedSettings: Hashable, Sendable {

  /// The cmd2 of each Get Operating Flags acknowledgment, by its request.
  public var operatingFlags: [OperatingFlagsRequest: UInt8]

  /// The values of each extended Get's reply, by button or group.
  public var values: [UInt8: [SettingName: UInt8]]

  /// Creates what a device reported.
  ///
  /// - Parameters:
  ///   - operatingFlags: The cmd2 of each Get Operating Flags acknowledgment. Defaults to none.
  ///   - values: The values of each extended Get's reply, by button. Defaults to none.
  public init(operatingFlags: [OperatingFlagsRequest: UInt8] = [:], values: [UInt8: [SettingName: UInt8]] = [:]) {

    self.operatingFlags = operatingFlags
    self.values = values

  }

  /// The byte a device reported for an item, or `nil` if it didn't: a Get Operating Flags
  /// reply's cmd2 for a flag or reading, and a value's byte for a value.
  ///
  /// - Parameters:
  ///   - item: The item.
  ///   - button: The button or group whose extended Get to read a value from.
  /// - Returns: The byte.
  public func raw(for item: SettingItem, button: UInt8 = 0x01) -> UInt8? {

    switch item.source {
    case let .flag(flag):
      operatingFlags[flag.query]
    case let .reading(reading):
      operatingFlags[reading.query]
    case let .value(value):
      values[button]?[value.name]
    }

  }

}

/// One line of `insteon device ADDRESS settings`, and its JSON.
public struct SettingLine: Hashable, Sendable, Encodable {

  /// The section, such as `"Load"`, or `"Other"` when the catalog gives none.
  public var section: String

  /// The setting's name in the catalog, such as `"rampRate"`.
  public var name: String

  /// What to call the setting, such as `"Ramp rate"`.
  public var label: String

  /// The button or group, for a value that's per button, or `nil`.
  public var button: Int?

  /// The value as shown, such as `"0.5 s"` or `"on"`, or `nil` if the device didn't report it.
  public var value: String?

  /// The byte the value was read from, such as `"0x1C"`, or `nil` if the device didn't report
  /// it. A flag's is its reply's whole cmd2.
  public var raw: String?

  /// The value as the device leaves the factory, if the catalog gives it.
  public var defaultValue: String?

  /// Whether the catalog gives a way to change the setting.
  public var isWritable: Bool

  /// Whether the catalog keeps the setting out of sight unless asked.
  public var isAdvanced: Bool

  /// Creates a line.
  ///
  /// - Parameters:
  ///   - section: The section.
  ///   - name: The setting's name.
  ///   - label: What to call the setting.
  ///   - button: The button or group, for a value that's per button.
  ///   - value: The value as shown.
  ///   - raw: The byte the value was read from.
  ///   - defaultValue: The value as the device leaves the factory.
  ///   - isWritable: Whether the setting can be changed.
  ///   - isAdvanced: Whether the setting is advanced.
  public init(
    section: String,
    name: String,
    label: String,
    button: Int? = nil,
    value: String?,
    raw: String?,
    defaultValue: String? = nil,
    isWritable: Bool,
    isAdvanced: Bool = false
  ) {

    self.section = section
    self.name = name
    self.label = label
    self.button = button
    self.value = value
    self.raw = raw
    self.defaultValue = defaultValue
    self.isWritable = isWritable
    self.isAdvanced = isAdvanced

  }

  /// The label, with the button for a value that's per button, such as
  /// `"Ramp rate (button 2)"`.
  public var title: String {

    button.map { "\(label) (button \($0))" } ?? label

  }

  /// The value, or `"not reported"`.
  public var valueText: String {

    value ?? "not reported"

  }

  /// The notes after the value: its default, and whether it can be changed, such as
  /// `"default 0.5 s, writable"`.
  public var notes: String {

    let access: String = isWritable ? "writable" : "read-only"

    guard let defaultValue else {

      return access

    }

    return "default \(defaultValue), \(access)"

  }

}

/// The lines `insteon device ADDRESS settings` prints, from what the Insteon device catalog
/// says about the settings and what the device reported.
public enum SettingsText {

  /// The section of items the catalog gives none.
  public static let otherSection = "Other"

  /// A flag's state in words.
  ///
  /// - Parameter isSet: Whether the bit is 1.
  /// - Returns: `"on"` or `"off"`.
  public static func flag(_ isSet: Bool) -> String {

    isSet ? "on" : "off"

  }

  /// An item's value as shown, from the byte the device reported.
  ///
  /// - Parameters:
  ///   - item: The item.
  ///   - raw: The byte: a Get Operating Flags reply's cmd2 for a flag or reading, and a
  ///     value's byte for a value.
  ///   - commands: The item's command set.
  /// - Returns: `"on"` or `"off"` for a flag, the number for a reading, and the value as the
  ///   command set shows it for a value.
  public static func value(of item: SettingItem, raw: UInt8, in commands: CommandSet) -> String {

    switch item.source {
    case let .flag(flag):
      Self.flag(raw & flag.bit != 0)
    case .reading:
      String(raw)
    case let .value(value):
      commands.text(for: value, raw: raw)
    }

  }

  /// An item's default as shown, if the catalog gives it.
  ///
  /// - Parameters:
  ///   - item: The item.
  ///   - commands: The item's command set.
  /// - Returns: The default, or `nil`.
  public static func defaultValue(of item: SettingItem, in commands: CommandSet) -> String? {

    switch item.source {
    case let .flag(flag):
      flag.defaultValue.map(Self.flag)
    case .reading:
      nil
    case let .value(value):
      value.defaultValue.map { commands.text(for: value, raw: $0) }
    }

  }

  /// What values a setting takes, for an error, such as
  /// `"a label such as 0.5 s, or a byte such as 0x1C"`.
  ///
  /// - Parameters:
  ///   - value: The setting.
  ///   - commands: Its command set.
  /// - Returns: The description.
  public static func expectedInput(for value: SettingValue, in commands: CommandSet) -> String {

    var kinds: [String] = []

    if let name = value.table, let table = commands.valueTable(named: name), !table.entries.isEmpty {

      let labels: [String] = table.entries.prefix(3).map(\.label)

      kinds.append("a label such as " + labels.joined(separator: ", "))

    } else if value.kind == .buttons {

      kinds.append("buttons such as 1,3, or none")

    } else if let unit = value.unit {

      kinds.append("a number in \(unit.rawValue) such as 50\(unit.symbol)")

    } else if let range = value.range {

      kinds.append("a number from \(range.lowerBound) to \(range.upperBound)")

    }

    let lowest: UInt8 = value.range?.lowerBound ?? 0x00
    let highest: UInt8 = value.range?.upperBound ?? 0xFF

    kinds.append("a byte from \(Hex.byte(lowest)) to \(Hex.byte(highest))")

    return kinds.joined(separator: ", or ")

  }

  /// Why the text given for a setting couldn't be used, as a sentence.
  ///
  /// - Parameters:
  ///   - error: The error reading the text threw, usually a `SettingInputError`.
  ///   - value: The setting.
  ///   - label: What to call the setting.
  ///   - commands: Its command set.
  /// - Returns: The sentence.
  public static func inputProblem(_ error: any Error, value: SettingValue, label: String, in commands: CommandSet) -> String {

    let expected: String = expectedInput(for: value, in: commands)

    switch error as? SettingInputError {
    case let .unreadable(_, text)?:
      return "'\(text)' isn't a value \(label) takes: expected \(expected)."
    case .outOfRange?:
      return "That's outside what \(label) takes: expected \(expected)."
    case nil:
      return "That isn't a value \(label) takes: expected \(expected)."
    }

  }

  /// The lines for a device's settings, in the catalog's order of sections.
  ///
  /// A value that's per button gets a line for each button asked about; everything else gets
  /// one line, from button 1's extended Get.
  ///
  /// - Parameters:
  ///   - commands: The device's command set.
  ///   - reported: What the device reported.
  ///   - buttons: The buttons or groups whose values were asked for, with button 1 first.
  ///   - showsAdvanced: Whether to include advanced settings.
  /// - Returns: The lines.
  public static func lines(for commands: CommandSet, reported: ReportedSettings, buttons: [UInt8] = [0x01], showsAdvanced: Bool) -> [SettingLine] {

    var lines: [SettingLine] = []

    for item in commands.settingItems where showsAdvanced || !item.isAdvanced {

      for button in Self.buttons(for: item, in: commands, asked: buttons) {

        lines.append(line(for: item, button: button, in: commands, reported: reported))

      }

    }

    return lines

  }

  /// The buttons an item gets a line for, or `nil` alone for an item that isn't per button.
  private static func buttons(for item: SettingItem, in commands: CommandSet, asked: [UInt8]) -> [UInt8?] {

    guard
      case .value = item.source,
      let settings = commands.extendedSettings,
      settings.isValuePerButton(item.name),
      asked.count > 1
    else {

      return [nil]

    }

    return asked.map { Optional($0) }

  }

  private static func line(for item: SettingItem, button: UInt8?, in commands: CommandSet, reported: ReportedSettings) -> SettingLine {

    let raw: UInt8? = reported.raw(for: item, button: button ?? 0x01)
    let value: String? = raw.map { Self.value(of: item, raw: $0, in: commands) }
    let rawText: String? = raw.map(Hex.byte)

    return SettingLine(
      section: item.section?.rawValue ?? otherSection,
      name: item.name.rawValue,
      label: item.label,
      button: button.map { Int($0) },
      value: value,
      raw: rawText,
      defaultValue: defaultValue(of: item, in: commands),
      isWritable: commands.isWritable(item),
      isAdvanced: item.isAdvanced
    )

  }

}
