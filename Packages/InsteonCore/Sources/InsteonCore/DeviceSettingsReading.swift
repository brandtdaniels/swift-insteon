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

  /// How many of the settings the catalog describes were left out of the reading because
  /// they're advanced and the reading didn't include them.
  public var advancedSettingsLeftOut: Int {

    commandSet.settingItems.count - items.count

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

  /// The text isn't a value the setting takes. The associated values are the text, the
  /// setting's label, and what the setting takes.
  case unreadableValue(String, label: String, accepts: DeviceSettingInput)

  /// The value is outside what the setting takes, or doesn't fit a byte. The associated values
  /// are the text, the setting's label, and what the setting takes.
  case valueOutOfRange(String, label: String, accepts: DeviceSettingInput)

  /// Writing the value also writes another the device didn't report, so nothing was written.
  /// The associated values are the setting's label and the other value's key.
  case missingValue(label: String, other: String)

  /// The catalog's command for the setting can't take the value, so nothing was written. The
  /// associated values are why, the setting's label and the value as a settings page shows it.
  case unwritableValue(DeviceSettingFieldProblem, label: String, value: String)

  /// The setting is one that's never written, because a wrong value can cut the device off
  /// from the modem or change the messages it understands: turning its radio or its
  /// powerline off, requiring a checksum in every message, or another flag the catalog guards
  /// with `FlagGuard.keep`; or writing it sends a command the catalog guards with
  /// `CommandGuard.never`. The associated value is its label. A value whose byte holds one of
  /// these flags is refused with the flag's label when writing it would change the flag, or
  /// when the device didn't report the byte before.
  case neverWritten(label: String)

  /// The setting is the programming lock, or another flag the catalog guards with
  /// `FlagGuard.neverSet`, which is never turned on, so a device is never left locked.
  /// Turning it off is allowed. The associated value is its label. A value whose byte holds
  /// such a flag is refused with the flag's label when it would set the flag's bit.
  case leavesProgrammingLocked(label: String)

  /// The device rejected Get Insteon Engine Version, as an i2CS device does when it isn't
  /// linked to the modem, so the form of Set Operating Flags it takes isn't known.
  case engineRejected

  /// The device reports a value other than the one written. The associated values are the
  /// setting's title, with its button for a setting that's per button, the value asked for and
  /// the value the device reports.
  case notChanged(title: String, requested: String, reported: String)

}

/// What a setting that holds a value takes, for saying what to give it when a value isn't
/// one it takes.
///
/// ```swift
/// do {
///   _ = try await lamp.writeSetting("rampRate", to: "fast")
/// } catch let DeviceSettingError.unreadableValue(text, label, accepts) {
///   if case let .label(examples, _) = accepts.form {
///     print("'\(text)' isn't a value \(label) takes, such as \(examples.joined(separator: ", ")).")
///   }
/// }
/// ```
public struct DeviceSettingInput: Hashable, Sendable {

  /// The form a value takes besides a byte.
  public enum Form: Hashable, Sendable {

    /// A label from the setting's value table, such as `"0.5 s"`. The associated values are
    /// up to three of the labels, in the table's order, and, when the table's entries stand
    /// for durations, the first duration written as someone could type it, such as `"2s"`.
    case label(examples: [String], durationExample: String?)

    /// Buttons, such as `"1,3"`, or `"none"`.
    case buttons

    /// A number in a unit. The associated values are the unit's name, such as `"percent"`,
    /// and the symbol a settings page writes after a number, such as `"%"`.
    case number(unit: String, symbol: String)

    /// A number between the bounds the catalog gives.
    case range(ClosedRange<UInt8>)

    /// Only a byte.
    case byte

  }

  /// The form a value takes besides a byte.
  public var form: Form

  /// The bytes the setting takes, which is every byte when the catalog gives no bounds.
  public var bytes: ClosedRange<UInt8>

  /// Creates what a setting takes.
  ///
  /// - Parameters:
  ///   - form: The form a value takes besides a byte.
  ///   - bytes: The bytes the setting takes.
  public init(form: Form, bytes: ClosedRange<UInt8>) {

    self.form = form
    self.bytes = bytes

  }

}

/// Why the catalog's command for a setting can't take a value.
public enum DeviceSettingFieldProblem: Hashable, Sendable {

  /// The value isn't the kind the command's parameter takes, such as a name for a number. The
  /// associated value is the parameter's name.
  case mismatchedKind(String)

  /// The value is outside what the command's parameter takes. The associated value is the
  /// parameter's name.
  case outOfRange(String)

  /// The command's parameter has no value by the name. The associated value is the
  /// parameter's name.
  case unknownName(String)

  /// The command has no parameter for the value. The associated value is the parameter's
  /// name.
  case missingValue(String)

  /// The problem a catalog's field error names.
  init(_ error: FieldError) {

    switch error {
    case let .mismatchedKind(name):
      self = .mismatchedKind(name.rawValue)
    case let .outOfRange(name):
      self = .outOfRange(name.rawValue)
    case let .unknownName(name):
      self = .unknownName(name.rawValue)
    case let .missingValue(name):
      self = .missingValue(name.rawValue)
    }

  }

}
