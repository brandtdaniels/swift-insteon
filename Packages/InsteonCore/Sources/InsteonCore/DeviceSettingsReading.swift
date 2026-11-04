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
/// after: the setting written, and any other setting whose value the write changed as well.
///
/// ```swift
/// let change = try await lamp.writeSetting("rampRate", to: "0.5 s")
///
/// for other in change.changedSettings {
///   print("Also changed: \(other.title): \(other.before) to \(other.after)")
/// }
/// ```
public struct DeviceSettingChange: Hashable, Sendable {

  /// Another setting whose value differs after the write, as the device reported it before
  /// and after.
  public struct OtherChange: Hashable, Sendable {

    /// The setting.
    public var setting: DeviceSetting

    /// The button or group, for a setting that's per button and was read for more than one;
    /// otherwise `nil`.
    public var button: Int?

    /// The value before the write, as a settings page shows it.
    public var before: String

    /// The value after the write, as a settings page shows it.
    public var after: String

    /// Creates a change to another setting.
    ///
    /// - Parameters:
    ///   - setting: The setting.
    ///   - button: The button or group, for a setting that's per button.
    ///   - before: The value before the write.
    ///   - after: The value after the write.
    public init(setting: DeviceSetting, button: Int?, before: String, after: String) {

      self.setting = setting
      self.button = button
      self.before = before
      self.after = after

    }

    /// The setting's label, with the button for a setting that's per button, such as
    /// `"On-level (button 2)"`.
    public var title: String {

      button.map { (number: Int) -> String in "\(setting.label) (button \(number))" } ?? setting.label

    }

  }

  /// Another setting the device reported before the write but not after it, so whether the
  /// write changed it isn't known.
  public struct UnreadSetting: Hashable, Sendable {

    /// The setting.
    public var setting: DeviceSetting

    /// The button or group, for a setting that's per button and was read for more than one;
    /// otherwise `nil`.
    public var button: Int?

    /// Creates an unread setting.
    ///
    /// - Parameters:
    ///   - setting: The setting.
    ///   - button: The button or group, for a setting that's per button.
    public init(setting: DeviceSetting, button: Int?) {

      self.setting = setting
      self.button = button

    }

    /// The setting's label, with the button for a setting that's per button, such as
    /// `"On-level (button 2)"`.
    public var title: String {

      button.map { (number: Int) -> String in "\(setting.label) (button \(number))" } ?? setting.label

    }

  }

  /// What the device's other writable settings did across the write: whether they were
  /// compared, each one that changed, and each one that couldn't be read again.
  ///
  /// It's a structure rather than an enumeration, and its ``Outcome`` and ``ReadFailure`` are
  /// open sets of named values, so a later outcome doesn't break code that checks for the
  /// ones it knows.
  public struct OtherSettings: Hashable, Sendable {

    /// How the comparison of the other settings ended.
    public struct Outcome: RawRepresentable, Hashable, Sendable {

      /// The name, as `insteon device ADDRESS set --json` prints it, such as `"compared"`.
      public var rawValue: String

      /// Creates an outcome from its name.
      ///
      /// - Parameter rawValue: The name.
      public init(rawValue: String) {

        self.rawValue = rawValue

      }

      /// The other settings were read before and after the write and compared.
      public static let compared = Outcome(rawValue: "compared")

      /// The catalog describes no other setting software can write, so nothing more was
      /// read.
      public static let nothingToCompare = Outcome(rawValue: "nothingToCompare")

      /// The device didn't answer the write's own read before it, or reported none of the
      /// other settings, so they weren't compared.
      public static let notReportedBefore = Outcome(rawValue: "notReportedBefore")

      /// The device didn't report the setting written afterward, so the write isn't confirmed
      /// and the other settings weren't read again.
      public static let notConfirmed = Outcome(rawValue: "notConfirmed")

      /// The write succeeded, but the other settings couldn't be read again, for the reason
      /// ``OtherSettings/rereadFailure`` gives, so what else it changed isn't known.
      public static let notReread = Outcome(rawValue: "notReread")

    }

    /// Why the other settings couldn't be read again after a write.
    public struct ReadFailure: RawRepresentable, Hashable, Sendable {

      /// The name, as `insteon device ADDRESS set --json` prints it, such as `"notAnswered"`.
      public var rawValue: String

      /// Creates a failure from its name.
      ///
      /// - Parameter rawValue: The name.
      public init(rawValue: String) {

        self.rawValue = rawValue

      }

      /// The device answered none of the reads.
      public static let notAnswered = ReadFailure(rawValue: "notAnswered")

      /// The connection to the modem closed.
      public static let connectionClosed = ReadFailure(rawValue: "connectionClosed")

      /// The task was canceled. It stays canceled, so the caller's next wait throws
      /// `CancellationError`.
      public static let canceled = ReadFailure(rawValue: "canceled")

      /// The modem failed another way.
      public static let failed = ReadFailure(rawValue: "failed")

    }

    /// How the comparison ended.
    public var outcome: Outcome

    /// Each other setting whose value differs after the write, in the order a settings page
    /// shows them; empty unless ``outcome`` is ``Outcome/compared``.
    public var changes: [OtherChange]

    /// Each other setting the device reported before the write but not after it, in the
    /// order a settings page shows them; empty unless ``outcome`` is ``Outcome/compared``.
    public var unread: [UnreadSetting]

    /// Why the other settings couldn't be read again, when ``outcome`` is
    /// ``Outcome/notReread``; otherwise `nil`.
    public var rereadFailure: ReadFailure?

    /// Creates what the other settings did.
    ///
    /// - Parameters:
    ///   - outcome: How the comparison ended.
    ///   - changes: Each other setting that changed. Defaults to none.
    ///   - unread: Each other setting that couldn't be read again. Defaults to none.
    ///   - rereadFailure: Why the other settings couldn't be read again. Defaults to `nil`.
    public init(outcome: Outcome, changes: [OtherChange] = [], unread: [UnreadSetting] = [], rereadFailure: ReadFailure? = nil) {

      self.outcome = outcome
      self.changes = changes
      self.unread = unread
      self.rereadFailure = rereadFailure

    }

    /// The other settings, compared.
    ///
    /// - Parameters:
    ///   - changes: Each one that changed.
    ///   - unread: Each one that couldn't be read again. Defaults to none.
    /// - Returns: The comparison.
    public static func compared(_ changes: [OtherChange], unread: [UnreadSetting] = []) -> OtherSettings {

      OtherSettings(outcome: .compared, changes: changes, unread: unread)

    }

    /// The other settings, not read again after a write that succeeded.
    ///
    /// - Parameter failure: Why.
    /// - Returns: The comparison.
    public static func notReread(_ failure: ReadFailure) -> OtherSettings {

      OtherSettings(outcome: .notReread, rereadFailure: failure)

    }

  }

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

  /// What the device's other settings did across the write.
  public var otherSettings: OtherSettings

  /// Creates a change.
  ///
  /// - Parameters:
  ///   - setting: The setting.
  ///   - button: The button or group written, for a setting that's per button.
  ///   - before: The value before.
  ///   - requested: The value asked for.
  ///   - after: The value the device reported afterward.
  ///   - otherSettings: What the device's other settings did across the write. Defaults to
  ///     ``OtherSettings/Outcome/nothingToCompare``.
  public init(
    setting: DeviceSetting,
    button: Int?,
    before: String?,
    requested: String,
    after: String?,
    otherSettings: OtherSettings = OtherSettings(outcome: .nothingToCompare)
  ) {

    self.setting = setting
    self.button = button
    self.before = before
    self.requested = requested
    self.after = after
    self.otherSettings = otherSettings

  }

  /// The other settings whose values differ after the write, or none when they weren't
  /// compared.
  public var changedSettings: [OtherChange] {

    otherSettings.changes

  }

  /// The other settings the device reported before the write but not after it.
  public var unreadSettings: [UnreadSetting] {

    otherSettings.unread

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
