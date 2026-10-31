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

/// The settings and commands that are never written, so no device is cut off from the modem,
/// left locked, or made to stop understanding it.
///
/// The Insteon device catalog marks them: an operating flag's or flags parameter bit's
/// `FlagGuard`, a command's `CommandGuard`, and a value's `SettingValue.flagsQuery`. A list
/// here is a floor under the catalog, so a catalog without those marks is guarded too: the
/// catalog can add guards, but never removes one of these.
enum DeviceSettingSafety {

  /// How a write treats a bit.
  enum Rule: Hashable, Sendable {

    /// A write leaves the bit as the device reported it.
    case keep

    /// A write may clear the bit but never sets it.
    case neverSet

  }

  /// A bit a value's byte holds that a write must guard, with the label of its flag.
  struct GuardedBit: Hashable, Sendable {

    /// The bit's mask in the byte.
    let mask: UInt8

    /// What a settings page calls the bit's flag.
    let label: String

    /// How a write treats the bit.
    let rule: Rule

  }

  /// The settings always kept as the device reported them, whatever the catalog says: turning
  /// off the radio or the powerline, and requiring a checksum in every message, which a modem
  /// that doesn't send one can't undo.
  static let neverWritten: Set<SettingName> = ["radioOff", "powerLineOff", "powerlineOff", "checksumRequired"]

  /// The programming lock, which is only ever turned off, whatever the catalog says.
  static let programmingLock: SettingName = "programmingLock"

  /// Set Operating Flags' cmd1, which the catalog's never-sent commands share.
  static let setOperatingFlagsCommand1: UInt8 = 0x20

  /// How a write treats a flag or bit: kept for a floor flag, a `keep` guard, or a guard this
  /// package doesn't know; never set for the programming lock or a `neverSet` guard; and
  /// written freely otherwise. The stricter rule wins.
  ///
  /// - Parameters:
  ///   - name: The flag's or bit's name.
  ///   - writeGuard: The catalog's guard for it, if any.
  /// - Returns: The rule, or `nil` if the bit is written freely.
  static func rule(named name: SettingName, writeGuard: FlagGuard?) -> Rule? {

    if neverWritten.contains(name) || (writeGuard != nil && writeGuard != .neverSet) {

      return .keep

    }

    if name == programmingLock || writeGuard == .neverSet {

      return .neverSet

    }

    return nil

  }

  /// How a write treats an operating flag.
  static func rule(for flag: OperatingFlag) -> Rule? {

    rule(named: flag.name, writeGuard: flag.writeGuard)

  }

  /// Whether the catalog marks a command as one an app never sends: any guard does, since a
  /// guard this package doesn't know is treated as the strictest.
  static func isNeverSent(_ commandGuard: CommandGuard?) -> Bool {

    commandGuard != nil

  }

  /// Commands never sent, whatever the catalog says, by their names in a command set: those
  /// that turn the programming lock on, the radio or the powerline off, or checksums on.
  static let neverSentNames: Set<SettingName> = [
    "programmingLockOn",
    "radioOff",
    "powerLineOff",
    "powerlineOff",
    "checksumOn",
    "checksumRequiredOn"
  ]

  /// Whether a standard command may be sent: it has no guard, isn't named as a command that's
  /// never sent, and, with a fixed cmd2, doesn't have the bytes of one.
  static func isSendable(_ command: DeviceStandardCommand, in commands: CommandSet?) -> Bool {

    guard !isNeverSent(command.sendGuard), !neverSentNames.contains(command.name) else {

      return false

    }

    guard case let .fixed(command2) = command.command2 else {

      return true

    }

    return !isNeverSent(Command(command1: command.command1, command2: command2), in: commands)

  }

  /// Whether an extended command may be sent: it has no guard, isn't named as a command that's
  /// never sent, and doesn't have the bytes of one.
  static func isSendable(_ command: DeviceExtendedCommand, in commands: CommandSet?) -> Bool {

    !isNeverSent(command.sendGuard) && !neverSentNames.contains(command.name) && !isNeverSent(command.command, in: commands)

  }

  /// The bytes never sent to a device that uses a command set, by whatever route or name.
  ///
  /// They're derived from the flags a write guards, whether the catalog guards them or the
  /// floor names them: Set Operating Flags (cmd1 `0x20`) with a kept flag's on or off cmd2,
  /// or a never-set flag's on cmd2, and the fixed bytes of the standard commands such a flag
  /// names to change it. Added to them are the Set Operating Flags bytes of every flag,
  /// standard or extended command the catalog guards, or the floor names in
  /// ``neverSentNames``. So a command set with no guards at all, such as one with only a
  /// programming lock flag or a `programmingLockOn` command, still never sends those bytes
  /// under another name.
  static func neverSentCommands(in commands: CommandSet?) -> Set<Command> {

    guard let commands else {

      return []

    }

    var never: Set<Command> = []

    func insertSetOperatingFlags(_ command2: UInt8?) {

      if let command2 {

        never.insert(Command(command1: setOperatingFlagsCommand1, command2: command2))

      }

    }

    func insertStandardCommand(named name: SettingName?) {

      guard let name, let command = commands.standardCommand(named: name), case let .fixed(command2) = command.command2 else {

        return

      }

      never.insert(Command(command1: command.command1, command2: command2))

    }

    for flag in commands.operatingFlags {

      switch rule(for: flag) {
      case .keep?:
        insertSetOperatingFlags(flag.on)
        insertSetOperatingFlags(flag.off)
        insertStandardCommand(named: flag.onCommand)
        insertStandardCommand(named: flag.offCommand)
      case .neverSet?:
        insertSetOperatingFlags(flag.on)
        insertStandardCommand(named: flag.onCommand)
      case nil:
        break
      }

    }

    for flagCommand in commands.flagCommands where isNeverSent(flagCommand.sendGuard) || neverSentNames.contains(flagCommand.name) {

      never.insert(flagCommand.command.command)

    }

    for standard in commands.standardCommands where standard.command1 == setOperatingFlagsCommand1 && (isNeverSent(standard.sendGuard) || neverSentNames.contains(standard.name)) {

      if case let .fixed(command2) = standard.command2 {

        never.insert(Command(command1: standard.command1, command2: command2))

      }

    }

    for extended in commands.extendedCommands where extended.command.command1 == setOperatingFlagsCommand1 && (isNeverSent(extended.sendGuard) || neverSentNames.contains(extended.name)) {

      never.insert(extended.command)

    }

    return never

  }

  /// Whether a command's bytes are ones never sent to a device that uses a command set, as
  /// ``neverSentCommands(in:)`` gives them. Every message a ``Device`` sends is checked.
  static func isNeverSent(_ command: Command, in commands: CommandSet?) -> Bool {

    neverSentCommands(in: commands).contains(command)

  }

  /// Whether an item is never written: a flag that's kept, or one named in the floor, or a
  /// value whose only write is a command the command set never sends.
  static func isNeverWritten(_ item: SettingItem, in commands: CommandSet) -> Bool {

    if neverWritten.contains(item.name) {

      return true

    }

    switch item.source {
    case let .flag(flag):
      return rule(for: flag) == .keep
    case .reading:
      return false
    case let .value(value):
      guard case let .extendedCommand(command) = commands.change(for: value) else {

        return false

      }

      return !isSendable(command, in: commands)
    }

  }

  /// Whether giving a flag a state would set a bit that's never set.
  static func setsNeverSetFlag(_ item: SettingItem, state: Bool) -> Bool {

    guard state, case let .flag(flag) = item.source else {

      return false

    }

    return rule(for: flag) == .neverSet

  }

  /// Whether a change to a flag sends a command the command set never sends.
  static func sendsNeverSentCommand(_ change: FlagChange, in commands: CommandSet) -> Bool {

    switch change {
    case let .setOperatingFlags(command2):
      return isNeverSent(Command(command1: setOperatingFlagsCommand1, command2: command2), in: commands)
    case let .standardCommand(command):
      return !isSendable(command, in: commands)
    }

  }

  /// Extended settings values whose byte is a Get Operating Flags reply's cmd2, by command set
  /// and value, with the request whose reply it is, for a catalog that doesn't give their
  /// `SettingValue.flagsQuery`. A value named `operatingFlags` in any command set is taken to
  /// be Get Operating Flags `0x00`'s byte too.
  static let operatingFlagsValues: [CommandSetID: [SettingName: OperatingFlagsRequest]] = [
    "openCloseSensor": ["configuration": .operatingFlags],
    "hiddenDoorSensor": ["operatingFlags": .operatingFlags]
  ]

  /// The value name that holds Get Operating Flags `0x00`'s byte in any command set.
  static let operatingFlagsValue: SettingName = "operatingFlags"

  /// The Get Operating Flags queries whose reply a value's byte may be: the catalog's
  /// `SettingValue.flagsQuery` and the floor's, both, so a catalog that names another query
  /// for a byte the floor lists never unguards it.
  static func flagsQueries(of value: SettingValue, in commands: CommandSet) -> Set<OperatingFlagsRequest> {

    var queries: Set<OperatingFlagsRequest> = []

    if let query = value.flagsQuery {

      queries.insert(query)

    }

    if let listed = operatingFlagsValues[commands.id]?[value.name] {

      queries.insert(listed)

    }

    if value.name == operatingFlagsValue {

      queries.insert(.operatingFlags)

    }

    return queries

  }

  /// The bits of a value's byte a write must guard: the guarded operating flags the byte
  /// holds, and the guarded bits of the flags parameter of the extended command that writes
  /// it.
  ///
  /// Writing such a byte writes every bit in it, so it never sets a bit that's never set, and
  /// never changes one that's kept.
  ///
  /// - Parameters:
  ///   - value: The value.
  ///   - commands: Its command set.
  /// - Returns: The bits, or none if the value's byte holds none.
  static func guardedBits(in value: SettingValue, of commands: CommandSet) -> [GuardedBit] {

    var bits: [GuardedBit] = []

    let queries: Set<OperatingFlagsRequest> = flagsQueries(of: value, in: commands)

    if !queries.isEmpty {

      for flag in commands.operatingFlags where queries.contains(flag.query) {

        if let flagRule = rule(for: flag) {

          bits.append(GuardedBit(mask: flag.bit, label: SettingItem(flag: flag).label, rule: flagRule))

        }

      }

    }

    if case let .extendedCommand(command) = commands.change(for: value), let parameter = parameter(of: command, for: value), case let .flags(fieldBits) = parameter.kind {

      for bit in fieldBits {

        if let bitRule = rule(named: bit.name, writeGuard: bit.writeGuard) {

          let label: String = commands.operatingFlag(named: bit.name).map { (flag: OperatingFlag) -> String in SettingItem(flag: flag).label } ?? bit.name.rawValue

          bits.append(GuardedBit(mask: bit.mask, label: label, rule: bitRule))

        }

      }

    }

    return bits

  }

  /// The parameter of an extended command a value is written into: the value's own, or else
  /// the command's only one, as `ValueChange.message(to:button:setting:to:current:)` chooses it.
  private static func parameter(of command: DeviceExtendedCommand, for value: SettingValue) -> MessageField? {

    let named: MessageField? = command.parameters.first { (field: MessageField) -> Bool in field.name == value.name }

    return named ?? (command.parameters.count == 1 ? command.parameters.first : nil)

  }

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

    let components = duration.components
    let milliseconds: Int64 = components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000

    if milliseconds % 1_000 == 0 {

      return String(milliseconds / 1_000) + "s"

    }

    return String(Double(milliseconds) / 1_000) + "s"

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
