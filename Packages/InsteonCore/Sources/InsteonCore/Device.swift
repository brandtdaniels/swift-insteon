import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// One device on a ``DeviceNetwork``, controlled as the Insteon device catalog describes it:
/// the way a front end turns it on and off, reads its status and settings, and changes them.
///
/// Get one from the network with ``DeviceNetwork/device(_:beforeIdentifying:)``. Every
/// decision about what the device can do comes from the catalog's group types for it: whether
/// a level means anything to a group, which command turns it on, and how to read its state.
/// A device the catalog doesn't describe is controlled by its category, as a dimmer when it
/// reported dimmable lighting control, `0x01`, and as a relay when it reported switched
/// lighting control, `0x02`. Any other device can only be pinged, and have its status read as
/// the raw byte Light Status Request reports.
///
/// ```swift
/// let lamp = network.device(InsteonAddress(0x1A, 0x2B, 0x3C))
///
/// let result = try await lamp.turnOn(level: 50)
/// if result.ignoredLevel != nil {
///   print("The lamp only turns on and off.")
/// }
///
/// let status = try await lamp.status()
/// print(status.isOn, status.percent ?? 100)
/// ```
///
/// An operation that needs to know what the device is looks it up in the network's
/// ``DeviceNetwork/registry``, and asks the device with ID Request when the registry doesn't
/// know it, through ``DeviceNetwork/identify(_:)``, which records what it reports. Status, and
/// turning a device on or off, record the device's level and when it answered in the network's
/// state, so the network's ``DeviceNetwork/snapshot()`` keeps them.
///
/// A device is a value: it holds only its address and the network, and keeps no state of its
/// own, since everything it learns belongs to the network, where every device and front end
/// sees it. So it's cheap to create for each operation, safe to pass between tasks, and its
/// operations run on the caller's task rather than wait their turn on another actor.
public struct Device: Sendable {

  /// The device's address.
  public let address: InsteonAddress

  /// The network the device is reached through.
  public let network: DeviceNetwork

  /// Called before the device is asked for its identity.
  private let beforeIdentifying: @Sendable () -> Void

  /// Creates a device on a network.
  ///
  /// ``DeviceNetwork/device(_:beforeIdentifying:)`` creates one too.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - network: The network the device is reached through.
  ///   - beforeIdentifying: Called before the device is asked for its identity, so an app can
  ///     say why it's waiting. Defaults to doing nothing.
  public init(address: InsteonAddress, network: DeviceNetwork, beforeIdentifying: @escaping @Sendable () -> Void = {}) {

    self.address = address
    self.network = network
    self.beforeIdentifying = beforeIdentifying

  }

  private var modem: any LinkingModem {

    network.modem

  }

  // MARK: - What the device is

  /// What the catalog says about the device, from the network's registry, or else from the
  /// identity the device reports to ID Request.
  ///
  /// - Returns: The description, or `nil` if the registry doesn't know the device and it
  ///   didn't report an identity, such as when it didn't answer or rejected a request.
  /// - Throws: ``DeviceControlError/notLinked`` when the device rejects the modem as an i2CS
  ///   device does before it's linked; `CancellationError` if the task is canceled while the
  ///   device is asked; and the errors of the modem and the connection to it, such as
  ///   `ModemError.connectionClosed`.
  public func deviceDescription() async throws -> DeviceDescription? {

    if let known = await network.registry.device(address) {

      return known.deviceDescription

    }

    beforeIdentifying()

    let identification: DeviceIdentification

    do {

      identification = try await network.identify(address)

    } catch let error as ModemError {

      // Only what the device itself did means its identity isn't known; the modem's and the
      // connection's errors are the caller's to handle.
      switch error {
      case .deviceRejected, .deviceTimedOut:
        return nil
      default:
        throw error
      }

    }

    guard identification.acceptsModem else {

      throw DeviceControlError.notLinked

    }

    return await network.registry.device(address)?.deviceDescription

  }

  /// What the device can do, for a front end to decide what to show.
  ///
  /// A group can be turned on and off, or has a status, only when its commands reach it apart
  /// from the device's other groups.
  ///
  /// - Returns: The device's groups, whether it dims and beeps, and its settings with their
  ///   controls.
  /// - Throws: The errors of ``deviceDescription()``.
  public func capabilities() async throws -> DeviceCapabilities {

    let model: DeviceControlModel = try await controlModel()
    let commands: CommandSet? = model.commandSet

    let groups: [DeviceGroup] = model.groups.map { (group: DeviceControlModel.Group) -> DeviceGroup in

      DeviceGroup(
        number: Int(group.number.rawValue),
        name: group.name,
        typeLabel: group.type.label,
        kind: DeviceGroupKind(rawValue: group.type.kind.rawValue),
        canDim: model.canDim(group),
        canTurnOnAndOff: model.canTurnOnAndOff(group),
        hasStatus: model.canRead(group),
        actionLabels: group.type.actions.map { (action: GroupType.Action) -> String in action.label }
      )

    }

    var settings: [DeviceSetting] = []

    if let commands {

      settings = commands.settingItems.map { (item: SettingItem) -> DeviceSetting in SettingPresentation.setting(for: item, in: commands) }

    }

    let source: DeviceCapabilities.Source

    switch model.source {
    case .catalog:
      source = .catalog
    case .categoryFallback:
      source = .categoryFallback
    case .uncontrolled:
      source = .uncontrolled
    }

    return DeviceCapabilities(
      productName: model.description?.displayName,
      isIdentified: model.description != nil,
      source: source,
      groups: groups,
      mainGroupNumber: model.mainGroupNumber.map { (number: AllLinkGroupNumber) -> Int in Int(number.rawValue) },
      canBeep: commands?.standardCommand(named: Self.beepCommand) != nil,
      settings: settings
    )

  }

  // MARK: - Control

  /// Turns one of the device's groups on with its type's `on` action.
  ///
  /// A level is sent only to a group that dims, whose `on` action takes its level from the
  /// caller. A group that only turns on and off is turned fully on, and the result's
  /// ``DeviceTurnOnResult/ignoredLevel`` says the level wasn't used. The action's command is a
  /// standard or an extended one, which is sent with its fixed user data and integrity bytes.
  ///
  /// - Parameters:
  ///   - level: The level, from 0 through 100 percent, or `nil` for fully on. Defaults to
  ///     `nil`.
  ///   - group: The group, or `nil` for the device's main group: group 1 when the catalog
  ///     gives its type, or else the first group whose type it gives. Defaults to `nil`.
  /// - Returns: What was done.
  /// - Throws: ``DeviceControlError`` when nothing says how to turn the group on, or its
  ///   command doesn't reach it apart from the device's other groups; the errors of
  ///   ``deviceDescription()``; and the modem's errors.
  public func turnOn(level: Int? = nil, group: Int? = nil) async throws -> DeviceTurnOnResult {

    let model: DeviceControlModel = try await controlModel()
    let target: DeviceControlModel.Group = try controlGroup(group, in: model, for: .turnOn)

    guard let on = target.type.action(named: DeviceControlModel.onAction) else {

      throw DeviceControlError.unsupported(.turnOn, product: model.product)

    }

    let dims: Bool = model.canDim(target)
    var value: UInt8 = 0xFF

    if dims, let level {

      value = LightLevel.level(percent: level)

    }

    let message: DeviceControlModel.ActionMessage = try model.message(for: on, of: target, value: value, to: address)

    guard model.canAddress(target, with: DeviceControlModel.onAction) else {

      throw DeviceControlError.unaddressable(.turnOn, group: Int(target.number.rawValue), product: model.product)

    }

    try await send(message)

    let sent: UInt8 = message.command.command2

    await network.recordAnswer(of: address, level: model.reportsDeviceLevel(target) ? sent : nil)

    return DeviceTurnOnResult(
      group: Int(target.number.rawValue),
      level: dims && level != nil ? LightLevel.percent(level: sent) : nil,
      ignoredLevel: dims ? nil : level
    )

  }

  /// Turns one of the device's groups off with its type's `off` action.
  ///
  /// - Parameter group: The group, or `nil` for the device's main group. Defaults to `nil`.
  /// - Throws: ``DeviceControlError`` when nothing says how to turn the group off, or its
  ///   command doesn't reach it apart from the device's other groups; the errors of
  ///   ``deviceDescription()``; and the modem's errors.
  public func turnOff(group: Int? = nil) async throws {

    let model: DeviceControlModel = try await controlModel()
    let target: DeviceControlModel.Group = try controlGroup(group, in: model, for: .turnOff)

    guard let off = target.type.action(named: DeviceControlModel.offAction) else {

      throw DeviceControlError.unsupported(.turnOff, product: model.product)

    }

    let message: DeviceControlModel.ActionMessage = try model.message(for: off, of: target, value: 0x00, to: address)

    guard model.canAddress(target, with: DeviceControlModel.offAction) else {

      throw DeviceControlError.unaddressable(.turnOff, group: Int(target.number.rawValue), product: model.product)

    }

    try await send(message)

    await network.recordAnswer(of: address, level: model.reportsDeviceLevel(target) ? 0x00 : nil)

  }

  /// Turns the device's main group on with Light On Fast, which ignores the ramp rate.
  ///
  /// The level follows the rules of ``turnOn(level:group:)``: it's sent only to a group that
  /// dims, and a group that only turns on and off is turned fully on. Light On Fast is the one
  /// the device's command set lists; a device whose commands the catalog doesn't describe is
  /// sent the one the Insteon protocol defines, and the result says so.
  ///
  /// - Parameter level: The level, from 0 through 100 percent, or `nil` for fully on.
  ///   Defaults to `nil`.
  /// - Returns: What was done.
  /// - Throws: ``DeviceControlError/unsupported(_:product:)`` when the command set doesn't list
  ///   Light On Fast, the other ``DeviceControlError`` refusals of ``turnOn(level:group:)``,
  ///   the errors of ``deviceDescription()``, and the modem's errors.
  public func turnOnFast(level: Int? = nil) async throws -> DeviceTurnOnResult {

    let (model, target, listed): (DeviceControlModel, DeviceControlModel.Group, DeviceStandardCommand?) = try await mainGroupCommand(Self.lightOnFastCommand, for: .turnOnFast)
    let dims: Bool = model.canDim(target)
    var value: UInt8 = 0xFF

    if dims, let level {

      value = LightLevel.level(percent: level)

    }

    let command: Command

    if let listed {

      command = try Self.command(listed, value: value)

    } else {

      command = StandardDirectCommand.fastOn(level: value).command

    }

    _ = try await modem.request(StandardMessage(to: address, command: command), timeout: network.requestTimeout)

    await network.recordAnswer(of: address, level: model.reportsDeviceLevel(target) ? command.command2 : nil)

    return DeviceTurnOnResult(
      group: Int(target.number.rawValue),
      level: dims && level != nil ? LightLevel.percent(level: command.command2) : nil,
      ignoredLevel: dims ? nil : level,
      isCommandDescribed: listed != nil
    )

  }

  /// Turns the device's main group off with Light Off Fast, which ignores the ramp rate.
  ///
  /// Light Off Fast is the one the device's command set lists; a device whose commands the
  /// catalog doesn't describe is sent the one the Insteon protocol defines, and the result says
  /// so.
  ///
  /// - Returns: What was done.
  /// - Throws: ``DeviceControlError/unsupported(_:product:)`` when the command set doesn't list
  ///   Light Off Fast, the other ``DeviceControlError`` refusals of ``turnOff(group:)``, the
  ///   errors of ``deviceDescription()``, and the modem's errors.
  @discardableResult
  public func turnOffFast() async throws -> DeviceTurnOffResult {

    let (model, target, listed): (DeviceControlModel, DeviceControlModel.Group, DeviceStandardCommand?) = try await mainGroupCommand(Self.lightOffFastCommand, for: .turnOffFast)
    let command: Command

    if let listed {

      command = try Self.command(listed, value: 0x00)

    } else {

      command = StandardDirectCommand.fastOff.command

    }

    _ = try await modem.request(StandardMessage(to: address, command: command), timeout: network.requestTimeout)

    await network.recordAnswer(of: address, level: model.reportsDeviceLevel(target) ? 0x00 : nil)

    return DeviceTurnOffResult(group: Int(target.number.rawValue), isCommandDescribed: listed != nil)

  }

  /// Changes the device's main group to a level at once, with Light Instant Change.
  ///
  /// A group that dims goes to the level. A group that only turns on and off is sent Light
  /// Instant Change for off at 0% and fully on otherwise, or, when its command set doesn't
  /// list Light Instant Change, its type's `off` action at 0% and `on` action otherwise. Light
  /// Instant Change is the one the device's command set lists; a device whose commands the
  /// catalog doesn't describe is sent the one the Insteon protocol defines, and the result
  /// says so.
  ///
  /// - Parameter level: The level, from 0 through 100 percent.
  /// - Returns: What was done.
  /// - Throws: ``DeviceControlError/unsupported(_:product:)`` when the command set doesn't list
  ///   Light Instant Change for a group that dims, the other ``DeviceControlError`` refusals
  ///   of ``turnOn(level:group:)``, the errors of ``deviceDescription()``, and the modem's
  ///   errors.
  @discardableResult
  public func changeInstantly(to level: Int) async throws -> DeviceInstantChangeResult {

    let model: DeviceControlModel = try await controlModel()
    let target: DeviceControlModel.Group = try controlGroup(nil, in: model, for: .instantChange)
    let dims: Bool = model.canDim(target)
    let percent: Int = min(max(level, 0), 100)
    let listed: DeviceStandardCommand? = model.commandSet?.standardCommand(named: Self.instantChangeCommand)
    let group: Int = Int(target.number.rawValue)

    if !dims, listed == nil {

      if percent == 0 {

        try await turnOff()

      } else {

        _ = try await turnOn()

      }

      return DeviceInstantChangeResult(group: group, level: percent, isOnOffOnly: true, isCommandDescribed: true)

    }

    if listed == nil, model.commandSet != nil {

      throw DeviceControlError.unsupported(.instantChange, product: model.product)

    }

    let value: UInt8 = dims ? LightLevel.level(percent: percent) : (percent == 0 ? 0x00 : 0xFF)
    let command: Command

    if let listed {

      command = try Self.command(listed, value: value)

    } else {

      command = StandardDirectCommand.instantChange(level: value).command

    }

    _ = try await modem.request(StandardMessage(to: address, command: command), timeout: network.requestTimeout)

    await network.recordAnswer(of: address, level: model.reportsDeviceLevel(target) ? command.command2 : nil)

    return DeviceInstantChangeResult(group: group, level: percent, isOnOffOnly: !dims, isCommandDescribed: listed != nil)

  }

  /// Reads one of the device's groups' state with the command its type names, and reads the
  /// reply as the type says: a level in percent for a group that dims, the name of the range
  /// the value is in, or on or off.
  ///
  /// A device nothing says how to read, or a main group whose type gives no state, is sent
  /// Light Status Request, and its reply is ``DeviceStatus/Reading/raw``. Only the main
  /// group's state, when it's the whole reply to Light Status Request, is recorded as the
  /// device's level.
  ///
  /// - Parameter group: The group, or `nil` for the device's main group. Defaults to `nil`.
  /// - Returns: The status.
  /// - Throws: ``DeviceControlError`` for a group the device doesn't have, or one whose state
  ///   command doesn't reach it apart from the device's other groups; the errors of
  ///   ``deviceDescription()``; and the modem's errors.
  public func status(group: Int? = nil) async throws -> DeviceStatus {

    let model: DeviceControlModel = try await controlModel()

    guard !model.groups.isEmpty else {

      if let group {

        throw model.description == nil ? DeviceControlError.notIdentified(.status) : DeviceControlError.noSuchGroup(group, product: model.product)

      }

      return try await rawStatus(group: nil)

    }

    let target: DeviceControlModel.Group = try controlGroup(group, in: model, for: .status)
    let number: Int = Int(target.number.rawValue)

    guard let state = target.type.state else {

      guard target.number == model.mainGroupNumber else {

        throw DeviceControlError.unaddressable(.status, group: number, product: model.product)

      }

      return try await rawStatus(group: number)

    }

    guard let command = model.standardCommand(named: state.command) else {

      throw DeviceControlError.missingCommand(state.command.rawValue, product: model.product)

    }

    guard model.canRead(target) else {

      throw DeviceControlError.unaddressable(.status, group: number, product: model.product)

    }

    let acknowledgment: ReceivedMessage = try await modem.request(
      StandardMessage(to: address, command: try command.command()),
      timeout: network.requestTimeout
    )
    let value: UInt8 = acknowledgment.command.command2
    let reading: (reading: DeviceStatus.Reading, isOn: Bool) = Self.reading(of: value, group: target, in: model, reply: command.reply)

    await network.recordAnswer(of: address, level: model.reportsDeviceLevel(target) ? value : nil)

    return DeviceStatus(
      group: number,
      value: value,
      allLinkDatabaseDelta: acknowledgment.command.command1,
      reading: reading.reading,
      isOn: reading.isOn
    )

  }

  /// Checks that the device answers, with Ping.
  ///
  /// - Throws: The modem's errors, such as `ModemError.deviceTimedOut` if the device doesn't
  ///   answer.
  public func ping() async throws {

    _ = try await modem.request(StandardMessage(to: address, command: StandardDirectCommand.ping), timeout: network.requestTimeout)

    await network.recordAnswer(of: address, level: nil)

  }

  /// Makes the device beep.
  ///
  /// Beep is harmless, and the catalog doesn't list it for every device that beeps, so it's
  /// sent whatever the catalog says: the Beep the device's command set lists, or else the one
  /// the Insteon protocol defines, even to a device whose identity isn't known. The result
  /// says whether the command set lists it.
  ///
  /// - Returns: Whether the device's command set lists Beep.
  /// - Throws: The modem's errors, such as `ModemError.deviceRejected` from a device that
  ///   isn't linked to the modem, and the errors of the modem and the connection to it while
  ///   the device is asked for its identity.
  @discardableResult
  public func beep() async throws -> DeviceBeepResult {

    let commands: CommandSet?

    do {

      commands = try await deviceDescription()?.commandSet

    } catch DeviceControlError.notLinked {

      // Beep is sent anyway, and the device's answer says why it didn't beep.
      commands = nil

    }

    let listed: DeviceStandardCommand? = commands?.standardCommand(named: Self.beepCommand)
    let command: Command

    if let listed {

      command = try listed.command()

    } else {

      command = StandardDirectCommand.beep.command

    }

    _ = try await modem.request(StandardMessage(to: address, command: command), timeout: network.requestTimeout)

    await network.recordAnswer(of: address, level: nil)

    return DeviceBeepResult(isListed: listed != nil)

  }

  // MARK: - Settings

  /// Reads the device's settings the catalog describes: each Get Operating Flags request they
  /// need, once, and an extended Get for button 1, then for each of the device's other groups
  /// when a value is per button.
  ///
  /// A request the device rejects or doesn't answer leaves its settings unreported, rather
  /// than failing the reading.
  ///
  /// - Parameters:
  ///   - includingAdvanced: Whether to read the settings a settings page keeps out of sight
  ///     unless asked. Defaults to `true`.
  ///   - beforeReading: Called once the settings are known and before the device is asked for
  ///     them, so an app can say that a reading has begun. Defaults to doing nothing.
  /// - Returns: The settings and what the device reported.
  /// - Throws: ``DeviceSettingError/notIdentified`` or ``DeviceSettingError/noSettings(product:)``
  ///   when the settings aren't known, the errors of ``deviceDescription()``, and the modem's
  ///   errors.
  public func readSettings(includingAdvanced: Bool = true, beforeReading: @Sendable () -> Void = {}) async throws -> DeviceSettingsReading {

    let (description, commands): (DeviceDescription, CommandSet) = try await describedSettings()
    let items: [SettingItem] = commands.settingItems.filter { (item: SettingItem) -> Bool in includingAdvanced || !item.isAdvanced }

    beforeReading()

    var flags: [OperatingFlagsRequest: UInt8] = [:]

    for query in Self.queries(of: items) {

      if let acknowledgment = try await answer(StandardMessage(to: address, command: StandardDirectCommand.getOperatingFlags(query))) {

        flags[query] = acknowledgment.command.command2

      }

    }

    let buttons: [UInt8] = Self.buttons(for: items, in: commands, description: description)
    var values: [UInt8: [SettingName: UInt8]] = [:]

    if let settings = commands.extendedSettings, items.contains(where: { (item: SettingItem) -> Bool in Self.isValue(item) }) {

      for button in buttons {

        if let reported = try await readValues(settings: settings, button: button) {

          values[button] = reported

        }

      }

    }

    return DeviceSettingsReading(
      productName: description.displayName,
      commandSet: commands,
      items: items,
      operatingFlags: flags,
      values: values,
      buttons: buttons
    )

  }

  /// Changes one of the device's settings, and reads it back to confirm the change.
  ///
  /// A flag is changed with Set Operating Flags, in the form the device takes: extended with a
  /// checksum for an i2CS device, extended with the command repeated while the flag the
  /// catalog names in `OperatingFlag.extendedWhen` is set, and standard otherwise; or with the
  /// standard command the catalog names for the state. A value is changed with an extended Set
  /// that keeps the other values it writes as the device reported them, or with the extended
  /// command the catalog names.
  ///
  /// - Parameters:
  ///   - key: The setting's key, such as `"rampRate"`, or its label, in any case.
  ///   - text: The value, such as `"on"`, `"0.5 s"`, `"50%"` or `"0x1C"`.
  ///   - button: The button or group, for a setting that's per button, or `nil` for button 1.
  ///     Defaults to `nil`.
  /// - Returns: The value before and after. A change the device didn't report afterward isn't
  ///   confirmed.
  /// - Throws: ``DeviceSettingError`` when the setting or the value isn't one the device takes,
  ///   or ``DeviceSettingError/notChanged(title:requested:reported:)`` when the device reports
  ///   another value afterward; ``DeviceControlError/noSuchGroup(_:product:)`` for a button
  ///   that isn't a group number; and the modem's errors.
  public func writeSetting(_ key: String, to text: String, button: Int? = nil) async throws -> DeviceSettingChange {

    let (description, commands): (DeviceDescription, CommandSet) = try await describedSettings()

    guard let item = commands.settingItem(named: key) else {

      throw DeviceSettingError.noSuchSetting(key, product: DeviceControlModel.product(of: description))

    }

    var buttonNumber: UInt8?

    if let button {

      guard let number = UInt8(exactly: button) else {

        throw DeviceControlError.noSuchGroup(button, product: DeviceControlModel.product(of: description))

      }

      buttonNumber = number

    }

    let setting: DeviceSetting = SettingPresentation.setting(for: item, in: commands)
    let change: DeviceSettingChange

    switch item.source {
    case .reading:
      throw DeviceSettingError.isReading(label: item.label)
    case let .flag(flag):
      change = try await write(flag, item: item, setting: setting, to: text, button: buttonNumber, description: description, commands: commands)
    case let .value(value):
      change = try await write(value, item: item, setting: setting, to: text, button: buttonNumber, commands: commands)
    }

    if change.isConfirmed {

      await network.recordAnswer(of: address, level: nil)

    }

    return change

  }

  // MARK: - Helpers

  /// The name of Beep in a command set.
  static let beepCommand: SettingName = "beep"

  /// The name of Light On Fast in a command set.
  static let lightOnFastCommand: SettingName = "lightOnFast"

  /// The name of Light Off Fast in a command set.
  static let lightOffFastCommand: SettingName = "lightOffFast"

  /// The name of Light Instant Change in a command set.
  static let instantChangeCommand: SettingName = "instantChange"

  /// The model of what the device can do, from its description.
  func controlModel() async throws -> DeviceControlModel {

    DeviceControlModel.make(try await deviceDescription())

  }

  /// The group an operation acts on.
  private func controlGroup(_ number: Int?, in model: DeviceControlModel, for operation: DeviceOperation) throws -> DeviceControlModel.Group {

    guard model.description != nil else {

      throw DeviceControlError.notIdentified(operation)

    }

    guard let number else {

      guard let main = model.mainGroup else {

        throw DeviceControlError.unsupported(operation, product: model.product)

      }

      return main

    }

    guard let byte = UInt8(exactly: number), let group = model.group(AllLinkGroupNumber(rawValue: byte)) else {

      throw DeviceControlError.noSuchGroup(number, product: model.product)

    }

    return group

  }

  /// Sends an action's message, a standard one with the network's timeout and an extended one
  /// with the timeout for extended requests.
  private func send(_ message: DeviceControlModel.ActionMessage) async throws {

    switch message {
    case let .standard(standard):
      _ = try await modem.request(standard, timeout: network.requestTimeout)
    case let .extended(extended):
      _ = try await modem.request(extended, timeout: Modem.defaultExtendedRequestTimeout)
    }

  }

  /// The device's model, its main group, and the command a command set lists by a name, for a
  /// command sent to the main group, such as Light On Fast.
  ///
  /// - Returns: The command, or `nil` when the catalog doesn't describe the device's commands,
  ///   so the one the Insteon protocol defines is sent.
  /// - Throws: ``DeviceControlError/unsupported(_:product:)`` when the command set doesn't list
  ///   the command, and the refusals of choosing the main group.
  private func mainGroupCommand(
    _ name: SettingName,
    for operation: DeviceOperation
  ) async throws -> (DeviceControlModel, DeviceControlModel.Group, DeviceStandardCommand?) {

    let model: DeviceControlModel = try await controlModel()
    let target: DeviceControlModel.Group = try controlGroup(nil, in: model, for: operation)

    guard let commands = model.commandSet else {

      return (model, target, nil)

    }

    guard let command = commands.standardCommand(named: name) else {

      throw DeviceControlError.unsupported(operation, product: model.product)

    }

    return (model, target, command)

  }

  /// A standard command's cmd1 and cmd2: its fixed cmd2, or else `value`.
  private static func command(_ command: DeviceStandardCommand, value: UInt8) throws -> Command {

    switch command.command2 {
    case .fixed:
      return try command.command()
    case .parameter:
      return try command.command(.unnamed(Int(value)))
    }

  }

  /// Sends Light Status Request and returns its reply as a raw byte. Nothing says the byte is
  /// the device's level, so only when the device answered is recorded.
  private func rawStatus(group: Int?) async throws -> DeviceStatus {

    let acknowledgment: ReceivedMessage = try await modem.request(
      StandardMessage(to: address, command: StandardDirectCommand.statusRequest()),
      timeout: network.requestTimeout
    )
    let value: UInt8 = acknowledgment.command.command2

    await network.recordAnswer(of: address, level: nil)

    return DeviceStatus(group: group, value: value, allLinkDatabaseDelta: acknowledgment.command.command1, reading: .raw, isOn: value != 0)

  }

  /// Reads a group's state from the byte its state command's acknowledgment carried.
  ///
  /// - Parameters:
  ///   - value: The byte.
  ///   - group: The group.
  ///   - model: The device's model.
  ///   - reply: What the command set says the acknowledgment carries, if anything.
  /// - Returns: For a state with a bit per group, the group's bit as on or off; for a group that
  ///   dims, whose reply is in percent, the level in percent; the name of the range the value
  ///   is in; on or off for a group that only turns on and off; and otherwise the raw byte.
  static func reading(
    of value: UInt8,
    group: DeviceControlModel.Group,
    in model: DeviceControlModel,
    reply: MessageField?
  ) -> (reading: DeviceStatus.Reading, isOn: Bool) {

    let isNonzero: Bool = value != 0

    guard let state = group.type.state else {

      return (.raw, isNonzero)

    }

    if state.isBitPerGroup {

      let number: Int = Int(group.number.rawValue)

      guard (1...8).contains(number) else {

        return (.raw, isNonzero)

      }

      let isOn: Bool = ((value >> UInt8(number - 1)) & 0x01) == 0x01

      return (.onOff(isOn), isOn)

    }

    if model.canDim(group), let reply, case let .number(_, _, unit) = reply.kind, unit == .percent, case let .number(number)? = reply.value(command2: value, userData: nil) {

      let percent: Int = min(max(Int(number.rounded()), 0), 100)

      return (.percent(percent), isNonzero)

    }

    if let range = state.ranges.first(where: { (range: GroupType.State.Range) -> Bool in range.values.contains(value) }) {

      return (.named(range.label), isNonzero)

    }

    if model.turnsOnAndOff(group) {

      return (.onOff(isNonzero), isNonzero)

    }

    return (.raw, isNonzero)

  }

  /// The device's description and command set, for its settings.
  private func describedSettings() async throws -> (DeviceDescription, CommandSet) {

    guard let description = try await deviceDescription() else {

      throw DeviceSettingError.notIdentified

    }

    guard let commands = description.commandSet else {

      throw DeviceSettingError.noSettings(product: DeviceControlModel.product(of: description))

    }

    return (description, commands)

  }

  /// The device's acknowledgment, or `nil` if it rejected the message or didn't answer.
  private func answer(_ message: StandardMessage) async throws -> ReceivedMessage? {

    do {

      return try await modem.request(message, timeout: network.requestTimeout)

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
  private func readValues(settings: ExtendedSettings, button: UInt8) async throws -> [SettingName: UInt8]? {

    let device: InsteonAddress = address
    let modem: any LinkingModem = self.modem
    let message = ExtendedMessage(to: device, command: ExtendedDirectCommand.getSet(), userData: settings.getUserData(button: button))
    let isPerButton: Bool = settings.isPerButton

    do {

      return try await modem.firstReply(
        within: Modem.defaultExtendedRequestTimeout,
        clock: network.clock,
        after: { () async throws -> Void in

          _ = try await modem.request(message, timeout: Modem.defaultExtendedRequestTimeout)

        },
        matching: { (reply: ModemReply) -> [SettingName: UInt8]? in

          guard case let .messageReceived(received) = reply, received.sender == device else {

            return nil

          }

          // A device whose values are per button says in D1 which button they're for.
          if isPerButton, received.userData?[1] != button {

            return nil

          }

          return settings.values(in: received)

        }
      )

    } catch let error as ModemError {

      switch error {
      case .deviceRejected, .deviceTimedOut:
        return nil
      default:
        throw error
      }

    }

  }

  /// The Get Operating Flags requests the items need, each once, in order.
  static func queries(of items: [SettingItem]) -> [OperatingFlagsRequest] {

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

  /// Whether an item is an extended settings value.
  static func isValue(_ item: SettingItem) -> Bool {

    if case .value = item.source {

      return true

    }

    return false

  }

  /// Button 1, then, when some of the items are values per button, the device's other groups,
  /// leaving out group 255.
  static func buttons(for items: [SettingItem], in commands: CommandSet, description: DeviceDescription) -> [UInt8] {

    guard
      let settings = commands.extendedSettings,
      settings.isPerButton,
      items.contains(where: { (item: SettingItem) -> Bool in settings.isValuePerButton(item.name) && Self.isValue(item) }),
      let profile = description.profile
    else {

      return [0x01]

    }

    let others: [UInt8] = profile.groups
      .map { (group: DeviceProfile.Group) -> UInt8 in group.number.rawValue }
      .filter { (number: UInt8) -> Bool in number > 1 && number < 0xFF }

    return [0x01] + Array(Set(others)).sorted()

  }

  // MARK: - Writing settings

  private func write(
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

    guard let change = commands.change(for: flag, setting: state) else {

      throw DeviceSettingError.noCommandForState(label: item.label, isOn: state)

    }

    let read = StandardMessage(to: address, command: flag.readCommand)
    let before: UInt8? = try await answer(read)?.command.command2

    switch change {
    case let .setOperatingFlags(command2):
      try await sendFlag(command2, flag: flag, description: description, commands: commands)
    case let .standardCommand(command):
      _ = try await modem.request(StandardMessage(to: address, command: try command.command()), timeout: network.requestTimeout)
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
  private func sendFlag(_ command2: UInt8, flag: OperatingFlag, description: DeviceDescription, commands: CommandSet) async throws {

    let command = StandardDirectCommand.setOperatingFlags(flag: command2)

    // An i2CS device gets the extended form with a checksum even when the flag names an
    // extendedWhen flag: i2CS is checked first, so the guarding flag isn't read for it.
    if try await engine(description) == .i2cs {

      _ = try await modem.request(ExtendedMessage(to: address, command: command), timeout: Modem.defaultExtendedRequestTimeout)

      return

    }

    if let name = flag.extendedWhen, let guarding = commands.operatingFlag(named: name) {

      let reply: ReceivedMessage? = try await answer(StandardMessage(to: address, command: guarding.readCommand))

      if let reply, guarding.isSet(in: reply) == true {

        let userData: UserData = DeviceStandardCommand.protectedUserData(for: command.command)
        let message = ExtendedMessage(to: address, command: command, userData: userData, integrity: UnprotectedIntegrity())

        _ = try await modem.request(message, timeout: Modem.defaultExtendedRequestTimeout)

        return

      }

    }

    _ = try await modem.request(StandardMessage(to: address, command: command), timeout: network.requestTimeout)

  }

  /// The device's engine, from the catalog or else from Get Insteon Engine Version.
  private func engine(_ description: DeviceDescription) async throws -> InsteonEngine? {

    if let engine = description.engine {

      return engine

    }

    let acknowledgment: ReceivedMessage

    do {

      acknowledgment = try await modem.request(StandardMessage(to: address, command: StandardDirectCommand.getEngineVersion), timeout: network.requestTimeout)

    } catch let error as ModemError {

      guard case .deviceRejected = error else {

        throw error

      }

      throw DeviceSettingError.engineRejected

    }

    return InsteonEngine(rawValue: acknowledgment.command.command2)

  }

  private func write(
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

      throw DeviceSettingError.unreadableValue(error, value: value, label: item.label, commandSet: commands)

    }

    let before: [SettingName: UInt8]? = try await readValues(settings: settings, button: target)
    let message: ExtendedMessage

    do {

      message = try change.message(to: address, button: target, setting: value.name, to: raw, current: before ?? [:])

    } catch SettingWriteError.missingValue(let other) {

      throw DeviceSettingError.missingValue(label: item.label, other: other)

    } catch let error as FieldError {

      throw DeviceSettingError.unwritableValue(error, label: item.label, value: commands.text(for: value, raw: raw))

    }

    _ = try await modem.request(message, timeout: Modem.defaultExtendedRequestTimeout)

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
