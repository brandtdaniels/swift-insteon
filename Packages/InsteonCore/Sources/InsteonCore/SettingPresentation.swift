import InsteonDeviceCatalog
import InsteonProtocol

/// How a settings page shows a command set's settings: their controls and values.
enum SettingPresentation {

  /// A flag's state in words: `"on"` or `"off"`.
  static func flagText(_ isSet: Bool) -> String {

    isSet ? "on" : "off"

  }

  /// The setting for an item, with its control.
  static func setting(for item: SettingItem, in commands: CommandSet) -> DeviceSetting {

    let control: DeviceSettingControl
    var isPerButton: Bool = false

    switch item.source {
    case .flag:
      control = .toggle
    case .reading:
      control = .reading
    case let .value(value):
      control = Self.control(for: value, in: commands)
      isPerButton = commands.extendedSettings?.isValuePerButton(value.name) ?? false
    }

    return DeviceSetting(
      key: item.name.rawValue,
      label: item.label,
      section: item.section?.rawValue,
      summary: item.summary,
      isAdvanced: item.isAdvanced,
      isWritable: commands.isWritable(item) && !DeviceSettingSafety.isNeverWritten(item, in: commands),
      isPerButton: isPerButton,
      control: control
    )

  }

  /// The control for an extended settings value.
  private static func control(for value: SettingValue, in commands: CommandSet) -> DeviceSettingControl {

    if let name = value.table, let table = commands.valueTable(named: name), !table.entries.isEmpty {

      return .choice(table.entries.map { (entry: ValueTable.Entry) -> String in entry.label })

    }

    if value.kind == .buttons {

      return .buttons

    }

    if value.unit != nil || value.scale != 1 {

      let range: ClosedRange<Double>? = value.range.map { (bounds: ClosedRange<UInt8>) -> ClosedRange<Double> in

        (Double(bounds.lowerBound) * value.scale)...(Double(bounds.upperBound) * value.scale)

      }

      return .number(range: range, unit: value.unit?.symbol)

    }

    if let range = value.range {

      return .number(range: Double(range.lowerBound)...Double(range.upperBound), unit: nil)

    }

    return .byte(range: nil)

  }

  /// An item's value as a settings page shows it: `"on"` or `"off"` for a flag, the number
  /// for a reading, and the value as the command set shows it for a value.
  static func text(of item: SettingItem, raw: UInt8, in commands: CommandSet) -> String {

    switch item.source {
    case let .flag(flag):
      flagText(raw & flag.bit != 0)
    case .reading:
      String(raw)
    case let .value(value):
      commands.text(for: value, raw: raw)
    }

  }

  /// What an extended settings value takes: a label from its value table, buttons, a number
  /// in its unit, or a number in its range, in that order of preference, and a byte.
  static func input(for value: SettingValue, in commands: CommandSet) -> DeviceSettingInput {

    let bytes: ClosedRange<UInt8> = value.range ?? UInt8.min...UInt8.max

    if let name = value.table, let table = commands.valueTable(named: name), !table.entries.isEmpty {

      let examples: [String] = table.entries.prefix(3).map { (entry: ValueTable.Entry) -> String in entry.label }

      return DeviceSettingInput(form: .label(examples: examples, durationExample: durationExample(in: table)), bytes: bytes)

    }

    if value.kind == .buttons {

      return DeviceSettingInput(form: .buttons, bytes: bytes)

    }

    if let unit = value.unit {

      return DeviceSettingInput(form: .number(unit: unit.rawValue, symbol: unit.symbol), bytes: bytes)

    }

    if let range = value.range {

      return DeviceSettingInput(form: .range(range), bytes: bytes)

    }

    return DeviceSettingInput(form: .byte, bytes: bytes)

  }

  /// The first duration a value table has, written as someone could type it, such as `2s` or
  /// `0.5s`.
  static func durationExample(in table: ValueTable) -> String? {

    guard let duration: Duration = table.entries.lazy.compactMap({ (entry: ValueTable.Entry) -> Duration? in entry.duration }).first else {

      return nil

    }

    // Whole seconds and milliseconds apart, so a duration of any length can't overflow.
    let components = duration.components
    let milliseconds: Int64 = components.attoseconds / 1_000_000_000_000_000

    if milliseconds == 0 {

      return String(components.seconds) + "s"

    }

    return String(Double(components.seconds) + Double(milliseconds) / 1_000) + "s"

  }

  /// An item's default as a settings page shows it, if the catalog gives it.
  static func defaultText(of item: SettingItem, in commands: CommandSet) -> String? {

    switch item.source {
    case let .flag(flag):
      flag.defaultValue.map(flagText)
    case .reading:
      nil
    case let .value(value):
      value.defaultValue.map { (raw: UInt8) -> String in commands.text(for: value, raw: raw) }
    }

  }

}
