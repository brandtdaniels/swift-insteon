import InsteonCore

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

/// The lines `insteon device ADDRESS settings` prints, and what `insteon device ADDRESS set`
/// says, from what InsteonCore read from or wrote to a device.
public enum SettingsText {

  /// The section of settings the catalog gives none.
  public static let otherSection = "Other"

  /// A flag's state in words.
  ///
  /// - Parameter isSet: Whether the bit is 1.
  /// - Returns: `"on"` or `"off"`.
  public static func flag(_ isSet: Bool) -> String {

    isSet ? "on" : "off"

  }

  /// The lines for a device's settings, in the catalog's order of sections: one for each of
  /// the reading's entries, so a value that's per button gets a line for each button read.
  ///
  /// - Parameter reading: The settings a device reported.
  /// - Returns: The lines.
  public static func lines(for reading: DeviceSettingsReading) -> [SettingLine] {

    reading.entries.map { (entry: DeviceSettingsReading.Entry) -> SettingLine in

      SettingLine(
        section: entry.setting.section ?? otherSection,
        name: entry.setting.key,
        label: entry.setting.label,
        button: entry.button,
        value: entry.text,
        raw: entry.raw.map(Hex.byte),
        defaultValue: entry.defaultText,
        isWritable: entry.setting.isWritable,
        isAdvanced: entry.setting.isAdvanced
      )

    }

  }

  /// What values a setting takes, for an error, such as
  /// `"a label such as 0.5 s, or a byte such as 0x1C"`. A value table whose entries stand
  /// for durations also takes a duration, such as `2s`.
  ///
  /// - Parameter input: What the setting takes.
  /// - Returns: The description.
  public static func expectedInput(_ input: DeviceSettingInput) -> String {

    var kinds: [String] = []

    switch input.form {
    case let .label(examples, durationExample):
      kinds.append("a label such as " + examples.joined(separator: ", "))

      if let durationExample {

        kinds.append("a duration such as " + durationExample)

      }
    case .buttons:
      kinds.append("buttons such as 1,3, or none")
    case let .number(unit, symbol):
      kinds.append("a number in \(unit) such as 50\(symbol)")
    case let .range(range):
      kinds.append("a number from \(range.lowerBound) to \(range.upperBound)")
    case .byte:
      break
    }

    kinds.append("a byte from \(Hex.byte(input.bytes.lowerBound)) to \(Hex.byte(input.bytes.upperBound))")

    return kinds.joined(separator: ", or ")

  }

  /// What `insteon device ADDRESS set` says a setting changed from and to, such as
  /// `"Ramp rate: 0.5 s → 0.1 s"`, and that it isn't confirmed when the device didn't report it
  /// afterward.
  ///
  /// - Parameter change: The change.
  /// - Returns: The line.
  public static func change(_ change: DeviceSettingChange) -> String {

    let before: String = change.before ?? "not reported"

    guard let after = change.after else {

      let what: String = change.setting.control == .toggle ? "flag" : "value"

      return "\(change.title): \(before) → \(change.requested), not confirmed: the device didn't report the \(what) afterward."

    }

    return "\(change.title): \(before) → \(after)"

  }

  /// Why a device's settings couldn't be read or a setting written, as a sentence.
  ///
  /// - Parameters:
  ///   - error: The error.
  ///   - device: The device's address, as it's printed.
  /// - Returns: The sentence.
  public static func failure(_ error: DeviceSettingError, device: String) -> String {

    switch error {
    case .notIdentified:
      return "\(device) didn't report its identity, so its settings can't be looked up. Check that it's linked and in range."
    case let .noSettings(product):
      return "The Insteon device catalog doesn't describe the settings of \(product)."
    case let .noSuchSetting(name, product):
      return "The Insteon device catalog has no setting '\(name)' for \(product). 'insteon device \(device) settings --advanced' lists them."
    case let .isReading(label):
      return "\(label) is a reading the device reports, so it can't be changed."
    case let .takesNoButton(label):
      return "\(label) is the whole device's, so it takes no --button."
    case let .unreadableState(text, label):
      return "'\(text)' isn't a state for \(label): expected on or off."
    case let .noCommandForState(label, isOn):
      return "\(label) can't be turned \(flag(isOn)) on this device: "
        + "the Insteon device catalog gives no command that does it."
    case let .readOnly(label):
      return "\(label) is read-only for this device: the Insteon device catalog gives no command that writes it."
    case let .unreadableValue(text, label, accepts):
      return "'\(text)' isn't a value \(label) takes: expected \(expectedInput(accepts))."
    case let .valueOutOfRange(_, label, accepts):
      return "That's outside what \(label) takes: expected \(expectedInput(accepts))."
    case let .missingValue(label, other):
      return "Writing \(label) also writes \(other), which the device didn't report, so nothing was changed."
    case let .unwritableValue(problem, label, value):
      return "The Insteon device catalog's command for \(label) can't take \(value): \(fieldProblem(problem)), so nothing was changed."
    case .engineRejected:
      return "\(device) rejected Get Insteon Engine Version, as an i2CS device does when it isn't linked to the modem, "
        + "so its settings can't be written. Link it first with 'insteon link \(device)'."
    case let .notChanged(title, requested, reported):
      return "\(title) wasn't changed to \(requested): the device reports \(reported)."
    case let .neverWritten(label):
      return "\(label) is never changed, since a wrong value can cut the device off from the modem."
    case let .leavesProgrammingLocked(label):
      return "\(label) is never turned on, so the device isn't left locked. Turning it off is allowed."
    }

  }

  /// Why a catalog's extended command couldn't take a value, as a clause.
  private static func fieldProblem(_ problem: DeviceSettingFieldProblem) -> String {

    switch problem {
    case let .mismatchedKind(name):
      "its parameter \(name) is a different kind of value"
    case let .outOfRange(name):
      "it's outside what its parameter \(name) takes"
    case let .unknownName(name):
      "its parameter \(name) has no such name"
    case let .missingValue(name):
      "it has no parameter for \(name)"
    }

  }

}
