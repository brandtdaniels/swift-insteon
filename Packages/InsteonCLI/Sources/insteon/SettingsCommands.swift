import InsteonCLICore
import InsteonDeviceCatalog
import InsteonModem
import InsteonProtocol

/// `insteon device ADDRESS settings` and `set`: reads and changes the settings the Insteon
/// device catalog describes, with the catalog's commands.
enum SettingsCommands {

  // MARK: - settings

  static func show(_ device: InsteonAddress, showsAdvanced: Bool, modem: Modem, names: ProductNames, printsJSON: Bool) async throws {

    let (known, commands) = try await describedDevice(device, modem: modem, names: names)
    let items: [SettingItem] = commands.settingItems.filter { showsAdvanced || !$0.isAdvanced }

    Output.note("Reading the settings of \(device)...")

    var reported = ReportedSettings()

    for query in queries(of: items) {

      let request = StandardMessage(to: device, command: StandardDirectCommand.getOperatingFlags(query))

      if let acknowledgment = try await answer(to: request, modem: modem) {

        reported.operatingFlags[query] = acknowledgment.command.command2

      }

    }

    let asked: [UInt8] = Self.buttons(for: items, in: commands, known: known)

    if let settings = commands.extendedSettings, items.contains(where: { Self.isValue($0) }) {

      for button in asked {

        if let values = try await readValues(of: device, settings: settings, button: button, modem: modem) {

          reported.values[button] = values

        }

      }

    }

    let lines: [SettingLine] = SettingsText.lines(for: commands, reported: reported, buttons: asked, showsAdvanced: showsAdvanced)

    if printsJSON {

      try Output.json(lines)

      return

    }

    printLines(lines, device: device, known: known)

    let hidden: Int = commands.settingItems.count - items.count

    if hidden > 0 {

      Output.line("\(Wording.count(hidden, "advanced setting")) not shown; --advanced shows them.")

    }

    if lines.contains(where: \.isWritable) {

      Output.line("Change a writable one with 'insteon device \(device) set NAME VALUE'.")

    }

  }

  private static func printLines(_ lines: [SettingLine], device: InsteonAddress, known: KnownDevice) {

    let product: String = known.productName.map { ", " + $0 } ?? ""

    Output.line("Settings of \(device)\(product):")

    var rows: [[String]] = []
    var section: String?

    for line in lines {

      if line.section != section {

        rows.append([""])
        rows.append([line.section])
        section = line.section

      }

      rows.append(["  " + line.title + ":", line.valueText, line.notes])

    }

    Output.table(rows)
    Output.line()

  }

  /// The Get Operating Flags requests the items need, each once, in order.
  private static func queries(of items: [SettingItem]) -> [OperatingFlagsRequest] {

    var queries: [OperatingFlagsRequest] = []

    for item in items {

      let query: OperatingFlagsRequest?

      switch item.source {
      case let .flag(flag):
        query = flag.query
      case let .reading(reading):
        query = reading.query
      case .value:
        query = nil
      }

      if let query, !queries.contains(query) {

        queries.append(query)

      }

    }

    return queries

  }

  private static func isValue(_ item: SettingItem) -> Bool {

    if case .value = item.source {

      return true

    }

    return false

  }

  /// Button 1, then, when some of the items are per button, the device's other groups.
  private static func buttons(for items: [SettingItem], in commands: CommandSet, known: KnownDevice) -> [UInt8] {

    guard
      let settings = commands.extendedSettings,
      settings.isPerButton,
      items.contains(where: { settings.isValuePerButton($0.name) && Self.isValue($0) }),
      let profile = known.profile
    else {

      return [0x01]

    }

    let others: [UInt8] = profile.groups.map(\.number.rawValue).filter { $0 > 1 && $0 < 0xFF }

    return [0x01] + Array(Set(others)).sorted()

  }

  // MARK: - set

  static func set(_ request: SettingRequest, device: InsteonAddress, modem: Modem, names: ProductNames) async throws {

    let (known, commands) = try await describedDevice(device, modem: modem, names: names)

    guard let item = commands.settingItem(named: request.name) else {

      throw CommandFailure(description: "The Insteon device catalog has no setting '\(request.name)' for \(product(known)). 'insteon device \(device) settings --advanced' lists them.")

    }

    switch item.source {
    case .reading:
      throw CommandFailure(description: "\(item.label) is a reading the device reports, so it can't be changed.")
    case let .flag(flag):
      try await set(flag, item: item, to: request, device: device, known: known, commands: commands, modem: modem)
    case let .value(value):
      try await set(value, item: item, to: request, device: device, commands: commands, modem: modem)
    }

  }

  private static func set(
    _ flag: OperatingFlag,
    item: SettingItem,
    to request: SettingRequest,
    device: InsteonAddress,
    known: KnownDevice,
    commands: CommandSet,
    modem: Modem
  ) async throws {

    if request.button != nil {

      throw CommandFailure(description: "\(item.label) is the whole device's, so it takes no --button.")

    }

    guard let state = OperatingFlag.state(parsing: request.value) else {

      throw CommandFailure(description: "'\(request.value)' isn't a state for \(item.label): expected on or off.")

    }

    guard let change = commands.change(for: flag, setting: state) else {

      throw CommandFailure(
        description: "The Insteon device catalog gives no way to turn \(item.label) \(SettingsText.flag(state)): "
          + "no Set Operating Flags cmd2 or standard command for it, so it can't be changed here."
      )

    }

    let read = StandardMessage(to: device, command: flag.readCommand)
    let before: UInt8? = try await answer(to: read, modem: modem)?.command.command2

    switch change {
    case let .setOperatingFlags(command2):
      try await sendFlag(command2, flag: flag, device: device, known: known, commands: commands, modem: modem)
    case let .standardCommand(command):
      try await modem.request(StandardMessage(to: device, command: try command.command()))
    }

    let after: UInt8? = try await answer(to: read, modem: modem)?.command.command2

    Output.line("\(item.label): \(flagText(before, flag: flag)) → \(flagText(after, flag: flag))")

  }

  private static func flagText(_ command2: UInt8?, flag: OperatingFlag) -> String {

    command2.map { SettingsText.flag($0 & flag.bit != 0) } ?? "not reported"

  }

  /// Sends Set Operating Flags as the device expects it: extended with a checksum for i2CS,
  /// extended with the command repeated when the flag's `extendedWhen` flag is set, and
  /// standard otherwise.
  private static func sendFlag(
    _ command2: UInt8,
    flag: OperatingFlag,
    device: InsteonAddress,
    known: KnownDevice,
    commands: CommandSet,
    modem: Modem
  ) async throws {

    let command = StandardDirectCommand.setOperatingFlags(flag: command2)

    if try await engine(of: device, known: known, modem: modem) == .i2cs {

      try await modem.request(ExtendedMessage(to: device, command: command))

      return

    }

    if let name = flag.extendedWhen, let guarding = commands.operatingFlag(named: name) {

      let reply: ReceivedMessage? = try await answer(to: StandardMessage(to: device, command: guarding.readCommand), modem: modem)

      if let reply, guarding.isSet(in: reply) == true {

        let userData: UserData = DeviceStandardCommand.protectedUserData(for: command.command)

        try await modem.request(ExtendedMessage(to: device, command: command, userData: userData, integrity: UnprotectedIntegrity()))

        return

      }

    }

    try await modem.request(StandardMessage(to: device, command: command))

  }

  /// The device's engine, from the catalog or else from Get Insteon Engine Version.
  private static func engine(of device: InsteonAddress, known: KnownDevice, modem: Modem) async throws -> InsteonEngine? {

    let identity = known.identity

    if let engine = known.profile?.engine(category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion) {

      return engine

    }

    let acknowledgment = try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.getEngineVersion))

    return InsteonEngine(rawValue: acknowledgment.command.command2)

  }

  private static func set(
    _ value: SettingValue,
    item: SettingItem,
    to request: SettingRequest,
    device: InsteonAddress,
    commands: CommandSet,
    modem: Modem
  ) async throws {

    guard let settings = commands.extendedSettings, let change = commands.change(for: value) else {

      throw CommandFailure(
        description: "The Insteon device catalog gives no way to write \(item.label): "
          + "no extended Set or extended command sets it, so it can't be changed here."
      )

    }

    let isPerButton: Bool = settings.isValuePerButton(value.name)

    if request.button != nil, !isPerButton {

      throw CommandFailure(description: "\(item.label) is the whole device's, so it takes no --button.")

    }

    let button: UInt8 = request.button ?? 0x01
    let raw: UInt8

    do {

      raw = try commands.raw(for: value, parsing: request.value)

    } catch {

      throw CommandFailure(description: SettingsText.inputProblem(error, value: value, label: item.label, in: commands))

    }

    let before: [SettingName: UInt8]? = try await readValues(of: device, settings: settings, button: button, modem: modem)
    let message: ExtendedMessage

    do {

      message = try change.message(to: device, button: button, setting: value.name, to: raw, current: before ?? [:])

    } catch SettingWriteError.missingValue(let other) {

      throw CommandFailure(description: "Writing \(item.label) also writes \(other), which the device didn't report, so nothing was changed.")

    }

    try await modem.request(message)

    let after: [SettingName: UInt8]? = try await readValues(of: device, settings: settings, button: button, modem: modem)
    let title: String = isPerButton ? "\(item.label) (button \(button))" : item.label
    let old: String = before?[value.name].map { commands.text(for: value, raw: $0) } ?? "not reported"
    let new: String = after?[value.name].map { commands.text(for: value, raw: $0) } ?? "not reported"

    Output.line("\(title): \(old) → \(new)")

  }

  // MARK: - Reading

  /// The device's identity and command set, or a failure that says why there's none.
  private static func describedDevice(_ device: InsteonAddress, modem: Modem, names: ProductNames) async throws -> (KnownDevice, CommandSet) {

    guard let known = try await Identities.known(device, modem: modem, names: names, asking: true) else {

      throw CommandFailure(description: "\(device) didn't report its identity, so its settings can't be looked up. Check that it's linked and in range.")

    }

    guard let commands = known.commandSet else {

      throw CommandFailure(description: "The Insteon device catalog doesn't describe the settings of \(product(known)).")

    }

    return (known, commands)

  }

  private static func product(_ known: KnownDevice) -> String {

    known.productName ?? "category \(known.identity.category), subcategory \(known.identity.subcategory)"

  }

  /// The device's acknowledgment, or `nil` if it rejected the message or didn't answer.
  private static func answer(to message: StandardMessage, modem: Modem) async throws -> ReceivedMessage? {

    do {

      return try await modem.request(message)

    } catch let error as ModemError {

      switch error {
      case .deviceRejected, .deviceTimedOut:
        return nil
      default:
        throw error
      }

    }

  }

  /// The values of an extended Get's reply for a button, or `nil` if the device rejected the
  /// Get or didn't reply.
  static func readValues(of device: InsteonAddress, settings: ExtendedSettings, button: UInt8, modem: Modem) async throws -> [SettingName: UInt8]? {

    let message = ExtendedMessage(to: device, command: ExtendedDirectCommand.getSet(), userData: settings.getUserData(button: button))
    let isPerButton: Bool = settings.isPerButton

    do {

      return try await modem.request(message, awaitingReply: { (reply: ReceivedMessage) -> [SettingName: UInt8]? in

        // A device whose values are per button says in D1 which button they're for.
        if isPerButton, reply.userData?[1] != button {

          return nil

        }

        return settings.values(in: reply)

      })

    } catch let error as ModemError {

      switch error {
      case .deviceRejected, .deviceTimedOut:
        return nil
      default:
        throw error
      }

    }

  }

}
