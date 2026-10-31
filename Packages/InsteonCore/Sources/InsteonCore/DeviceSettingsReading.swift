import InsteonDeviceCatalog
import InsteonProtocol

/// A device's settings, as ``Device/readSettings(includingAdvanced:beforeReading:)`` read
/// them: what the Insteon device catalog says about each, and the bytes the device reported.
///
/// ```swift
/// let reading = try await network.device(lamp).readSettings()
///
/// for entry in reading.entries {
///   print(entry.setting.label, entry.text ?? "not reported")
/// }
/// ```
public struct DeviceSettingsReading: Hashable, Sendable {

  /// One setting's value, for one button when it's per button.
  public struct Entry: Hashable, Sendable {

    /// The setting.
    public var setting: DeviceSetting

    /// The button or group, for a setting that's per button and was read for more than one;
    /// otherwise `nil`.
    public var button: Int?

    /// The byte the device reported, or `nil` if it didn't. A flag's is its reply's whole
    /// cmd2.
    public var raw: UInt8?

    /// The value as a settings page shows it, such as `"on"`, `"0.5 s"` or `"50%"`, or `nil`
    /// if the device didn't report it.
    public var text: String?

    /// The value as the device leaves the factory, as a settings page shows it, if the catalog
    /// gives it.
    public var defaultText: String?

    /// Creates an entry.
    ///
    /// - Parameters:
    ///   - setting: The setting.
    ///   - button: The button or group, for a setting that's per button.
    ///   - raw: The byte the device reported.
    ///   - text: The value as a settings page shows it.
    ///   - defaultText: The value as the device leaves the factory.
    public init(setting: DeviceSetting, button: Int?, raw: UInt8?, text: String?, defaultText: String?) {

      self.setting = setting
      self.button = button
      self.raw = raw
      self.text = text
      self.defaultText = defaultText

    }

  }

  /// The product's name and model, as the catalog gives them, or `nil` if the catalog doesn't
  /// have the device.
  public var productName: String?

  /// The device's command set, which describes the settings.
  public var commandSet: CommandSet

  /// The items that were read, in the order a settings page shows them.
  public var items: [SettingItem]

  /// The cmd2 of each Get Operating Flags acknowledgment, by its request.
  public var operatingFlags: [OperatingFlagsRequest: UInt8]

  /// The values of each extended Get's reply, by button or group.
  public var values: [UInt8: [SettingName: UInt8]]

  /// The buttons or groups whose values were asked for, with button 1 first.
  public var buttons: [UInt8]

  /// Creates a reading.
  ///
  /// - Parameters:
  ///   - productName: The product's name and model.
  ///   - commandSet: The device's command set.
  ///   - items: The items that were read.
  ///   - operatingFlags: The cmd2 of each Get Operating Flags acknowledgment.
  ///   - values: The values of each extended Get's reply, by button.
  ///   - buttons: The buttons whose values were asked for.
  public init(
    productName: String?,
    commandSet: CommandSet,
    items: [SettingItem],
    operatingFlags: [OperatingFlagsRequest: UInt8],
    values: [UInt8: [SettingName: UInt8]],
    buttons: [UInt8]
  ) {

    self.productName = productName
    self.commandSet = commandSet
    self.items = items
    self.operatingFlags = operatingFlags
    self.values = values
    self.buttons = buttons

  }

  /// The byte the device reported for an item, or `nil` if it didn't.
  ///
  /// - Parameters:
  ///   - item: The item.
  ///   - button: The button or group whose extended Get to read a value from. Defaults to 1.
  /// - Returns: A Get Operating Flags reply's cmd2 for a flag or reading, and a value's byte
  ///   for a value.
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

  /// Each item's value, with a value that's per button once for each button asked about when
  /// there was more than one.
  public var entries: [Entry] {

    var entries: [Entry] = []

    for item in items {

      let setting: DeviceSetting = SettingPresentation.setting(for: item, in: commandSet)
      let perButton: Bool = setting.isPerButton && buttons.count > 1
      let asked: [UInt8?] = perButton ? buttons.map { (button: UInt8) -> UInt8? in button } : [nil]

      for button in asked {

        let raw: UInt8? = self.raw(for: item, button: button ?? 0x01)

        entries.append(Entry(
          setting: setting,
          button: button.map { (number: UInt8) -> Int in Int(number) },
          raw: raw,
          text: raw.map { (byte: UInt8) -> String in SettingPresentation.text(of: item, raw: byte, in: commandSet) },
          defaultText: SettingPresentation.defaultText(of: item, in: commandSet)
        ))

      }

    }

    return entries

  }

}

/// What ``Device/writeSetting(_:to:button:)`` changed, as the device reported it before and
/// after.
public struct DeviceSettingChange: Hashable, Sendable {

  /// The setting.
  public var setting: DeviceSetting

  /// The button or group written, for a setting that's per button; otherwise `nil`.
  public var button: Int?

  /// The value before, as a settings page shows it, or `nil` if the device didn't report it.
  public var before: String?

  /// The value asked for, as a settings page shows it.
  public var requested: String

  /// The value the device reported afterward, as a settings page shows it, which is
  /// ``DeviceSettingChange/requested``; or `nil` if the device didn't report it, so the
  /// change isn't confirmed.
  public var after: String?

  /// Creates a change.
  ///
  /// - Parameters:
  ///   - setting: The setting.
  ///   - button: The button or group written, for a setting that's per button.
  ///   - before: The value before.
  ///   - requested: The value asked for.
  ///   - after: The value the device reported afterward.
  public init(setting: DeviceSetting, button: Int?, before: String?, requested: String, after: String?) {

    self.setting = setting
    self.button = button
    self.before = before
    self.requested = requested
    self.after = after

  }

  /// The setting's label, with the button for a setting that's per button, such as
  /// `"Ramp rate (button 2)"`.
  public var title: String {

    button.map { (number: Int) -> String in "\(setting.label) (button \(number))" } ?? setting.label

  }

  /// Whether the device reported the value afterward, so the change is confirmed.
  public var isConfirmed: Bool {

    after != nil

  }

}

/// Why a device's settings couldn't be read or a setting written.
public enum DeviceSettingError: Error, Sendable {

  /// The device's identity isn't known, and it didn't report one when asked, so its settings
  /// can't be looked up.
  case notIdentified

  /// The catalog doesn't describe the device's settings. The associated value is the product,
  /// as a sentence names it.
  case noSettings(product: String)

  /// The catalog has no setting by the name or label. The associated values are the name as
  /// given and the product.
  case noSuchSetting(String, product: String)

  /// The setting is a reading the device reports, so it can't be changed. The associated
  /// value is its label.
  case isReading(label: String)

  /// The setting is the whole device's, so it takes no button. The associated value is its
  /// label.
  case takesNoButton(label: String)

  /// The text isn't a state for a flag, which is on or off. The associated values are the
  /// text and the flag's label.
  case unreadableState(String, label: String)

  /// The catalog gives no command that turns the flag to the state. The associated values are
  /// the flag's label and the state.
  case noCommandForState(label: String, isOn: Bool)

  /// The catalog gives no command that writes the value. The associated value is its label.
  case readOnly(label: String)

  /// The text isn't a value the setting takes. The associated values are why, the setting,
  /// its label, and its command set, which says what it takes.
  case unreadableValue(SettingInputError, value: SettingValue, label: String, commandSet: CommandSet)

  /// Writing the value also writes another the device didn't report, so nothing was written.
  /// The associated values are the setting's label and the other value's name.
  case missingValue(label: String, other: SettingName)

  /// The catalog's command for the setting can't take the value, so nothing was written. The
  /// associated values are why, the setting's label and the value as a settings page shows it.
  case unwritableValue(FieldError, label: String, value: String)

  /// The device rejected Get Insteon Engine Version, as an i2CS device does when it isn't
  /// linked to the modem, so the form of Set Operating Flags it takes isn't known.
  case engineRejected

  /// The device reports a value other than the one written. The associated values are the
  /// setting's title, with its button for a setting that's per button, the value asked for and
  /// the value the device reports.
  case notChanged(title: String, requested: String, reported: String)

}

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
      isWritable: commands.isWritable(item),
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
