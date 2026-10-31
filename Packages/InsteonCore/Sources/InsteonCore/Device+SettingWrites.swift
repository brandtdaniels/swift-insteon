import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

// Writing the device's settings.
extension Device {

  func write(
    _ flag: OperatingFlag,
    item: SettingItem,
    setting: DeviceSetting,
    to text: String,
    button: UInt8?,
    description: DeviceDescription,
    commands: CommandSet
  ) async throws -> DeviceSettingChange {

    if button != nil {

      throw DeviceSettingError.takesNoButton(label: item.label)

    }

    guard let state = OperatingFlag.state(parsing: text) else {

      throw DeviceSettingError.unreadableState(text, label: item.label)

    }

    if DeviceSettingSafety.setsNeverSetFlag(item, state: state) {

      throw DeviceSettingError.leavesProgrammingLocked(label: item.label)

    }

    guard let change = commands.change(for: flag, setting: state) else {

      throw DeviceSettingError.noCommandForState(label: item.label, isOn: state)

    }

    // The same bytes as a command the catalog never sends are refused by any route.
    if DeviceSettingSafety.sendsNeverSentCommand(change, in: commands) {

      throw DeviceSettingError.neverWritten(label: item.label)

    }

    let read = StandardMessage(to: address, command: flag.readCommand)
    let before: UInt8? = try await answer(read)?.command.command2

    switch change {
    case let .setOperatingFlags(command2):
      try await sendFlag(command2, flag: flag, description: description, commands: commands)
    case let .standardCommand(command):
      _ = try await request(StandardMessage(to: address, command: try command.command()), timeout: network.requestTimeout, for: .setting(label: item.label))
    }

    let after: UInt8? = try await answer(read)?.command.command2
    let requested: String = SettingPresentation.flagText(state)
    let beforeText: String? = before.map { (byte: UInt8) -> String in SettingPresentation.flagText(byte & flag.bit != 0) }

    guard let reported = after else {

      return DeviceSettingChange(setting: setting, button: nil, before: beforeText, requested: requested, after: nil)

    }

    let isSet: Bool = reported & flag.bit != 0
    let reportedText: String = SettingPresentation.flagText(isSet)

    guard isSet == state else {

      throw DeviceSettingError.notChanged(title: item.label, requested: requested, reported: reportedText)

    }

    return DeviceSettingChange(setting: setting, button: nil, before: beforeText, requested: requested, after: reportedText)

  }

  /// Sends Set Operating Flags as the device takes it: extended with a checksum for i2CS,
  /// extended with the command repeated when the flag's `extendedWhen` flag is set, and
  /// standard otherwise.
  func sendFlag(_ command2: UInt8, flag: OperatingFlag, description: DeviceDescription, commands: CommandSet) async throws {

    try await sendSetOperatingFlags(
      command2,
      extendedWhen: flag.extendedWhen,
      description: description,
      commands: commands,
      purpose: .setting(label: SettingItem(flag: flag).label)
    )

  }

  /// Sends Set Operating Flags with a cmd2 as the device takes it: extended with a checksum
  /// for i2CS, extended with the command repeated when the `extendedWhen` flag is set, and
  /// standard otherwise.
  func sendSetOperatingFlags(
    _ command2: UInt8,
    extendedWhen: SettingName?,
    description: DeviceDescription,
    commands: CommandSet,
    purpose: SendPurpose
  ) async throws {

    let command = StandardDirectCommand.setOperatingFlags(flag: command2)

    // An i2CS device gets the extended form with a checksum even when the flag names an
    // extendedWhen flag: i2CS is checked first, so the guarding flag isn't read for it.
    if try await engine(description) == .i2cs {

      _ = try await request(ExtendedMessage(to: address, command: command), timeout: Modem.defaultExtendedRequestTimeout, for: purpose)

      return

    }

    if let name = extendedWhen, let guarding = commands.operatingFlag(named: name) {

      let reply: ReceivedMessage? = try await answer(StandardMessage(to: address, command: guarding.readCommand))

      if let reply, guarding.isSet(in: reply) == true {

        let userData: UserData = DeviceStandardCommand.protectedUserData(for: command.command)
        let message = ExtendedMessage(to: address, command: command, userData: userData, integrity: UnprotectedIntegrity())

        _ = try await request(message, timeout: Modem.defaultExtendedRequestTimeout, for: purpose)

        return

      }

    }

    _ = try await request(StandardMessage(to: address, command: command), timeout: network.requestTimeout, for: purpose)

  }

  /// The device's engine, from the catalog or else from Get Insteon Engine Version.
  func engine(_ description: DeviceDescription) async throws -> InsteonEngine? {

    if let engine = description.engine {

      return engine

    }

    let acknowledgment: ReceivedMessage

    do {

      acknowledgment = try await request(StandardMessage(to: address, command: StandardDirectCommand.getEngineVersion), timeout: network.requestTimeout, for: .control(.settings))

    } catch let error as ModemError {

      guard case .deviceRejected = error else {

        throw error

      }

      throw DeviceSettingError.engineRejected

    }

    return InsteonEngine(rawValue: acknowledgment.command.command2)

  }

  func write(
    _ value: SettingValue,
    item: SettingItem,
    setting: DeviceSetting,
    to text: String,
    button: UInt8?,
    commands: CommandSet
  ) async throws -> DeviceSettingChange {

    guard let settings = commands.extendedSettings, let change = commands.change(for: value) else {

      throw DeviceSettingError.readOnly(label: item.label)

    }

    let isPerButton: Bool = settings.isValuePerButton(value.name)

    if button != nil, !isPerButton {

      throw DeviceSettingError.takesNoButton(label: item.label)

    }

    let target: UInt8 = button ?? 0x01
    let raw: UInt8

    do throws(SettingInputError) {

      raw = try commands.raw(for: value, parsing: text)

    } catch {

      let accepts: DeviceSettingInput = SettingPresentation.input(for: value, in: commands)

      switch error {
      case let .unreadable(_, given):
        throw DeviceSettingError.unreadableValue(given, label: item.label, accepts: accepts)
      case .outOfRange:
        throw DeviceSettingError.valueOutOfRange(text, label: item.label, accepts: accepts)
      }

    }

    // A byte that holds operating flags writes them all, so it never sets a bit that's never
    // set, such as the programming lock's, and never changes a bit that's kept.
    let guardedBits: [DeviceSettingSafety.GuardedBit] = DeviceSettingSafety.guardedBits(in: value, of: commands)

    for bit in guardedBits where bit.rule == .neverSet && raw & bit.mask != 0 {

      throw DeviceSettingError.leavesProgrammingLocked(label: bit.label)

    }

    let before: [SettingName: UInt8]? = try await readValues(settings: settings, button: target)

    for bit in guardedBits where bit.rule == .keep {

      guard let current = before?[value.name], current & bit.mask == raw & bit.mask else {

        throw DeviceSettingError.neverWritten(label: bit.label)

      }

    }
    let message: ExtendedMessage

    do {

      message = try change.message(to: address, button: target, setting: value.name, to: raw, current: before ?? [:])

    } catch SettingWriteError.missingValue(let other) {

      throw DeviceSettingError.missingValue(label: item.label, other: other.rawValue)

    } catch let error as FieldError {

      throw DeviceSettingError.unwritableValue(DeviceSettingFieldProblem(error), label: item.label, value: commands.text(for: value, raw: raw))

    }

    _ = try await request(message, timeout: Modem.defaultExtendedRequestTimeout, for: .setting(label: item.label))

    let after: [SettingName: UInt8]? = try await readValues(settings: settings, button: target)
    let changedButton: Int? = isPerButton ? Int(target) : nil
    let beforeText: String? = before?[value.name].map { (byte: UInt8) -> String in commands.text(for: value, raw: byte) }
    let requested: String = commands.text(for: value, raw: raw)

    guard let reported = after?[value.name] else {

      return DeviceSettingChange(setting: setting, button: changedButton, before: beforeText, requested: requested, after: nil)

    }

    let written = DeviceSettingChange(setting: setting, button: changedButton, before: beforeText, requested: requested, after: requested)

    guard reported == raw else {

      throw DeviceSettingError.notChanged(title: written.title, requested: requested, reported: commands.text(for: value, raw: reported))

    }

    return written

  }

}
