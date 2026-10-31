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
        actionLabels: group.type.actions.map { (action: GroupType.Action) -> String in action.label },
        outputs: (group.type.outputs?.bits ?? []).map { (output: GroupType.Outputs.Output) -> DeviceOutput in

          DeviceOutput(key: output.name.rawValue, label: output.label)

        },
        outputsActiveWhen: group.type.outputs?.activeWhen.map { (condition: DeviceProfile.Group.Condition) -> DeviceFlagCondition in

          DeviceFlagCondition(flag: condition.flag.rawValue, isSet: condition.isSet)

        },
        armModes: group.type.armModes.map(\.rawValue)
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
      canBeep: commands.map { (commands: CommandSet) -> Bool in Self.sendableBeep(in: commands) != nil } ?? false,
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

    try await send(message, for: .turnOn)

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

    try await send(message, for: .turnOff)

    await network.recordAnswer(of: address, level: model.reportsDeviceLevel(target) ? 0x00 : nil)

  }

  /// Turns some of a group's outputs on, such as one of a ballast dimmer's two relays, with its
  /// type's `on` action, and leaves the others as they are.
  ///
  /// The catalog's ``DeviceGroup/outputs`` give each output a bit; the bits of the outputs
  /// named are ORed together into the action's parameter. When the catalog says the outputs
  /// are the load only while an operating flag is in a state, such as relay mode, the device is
  /// asked for the flag with Get Operating Flags first, and nothing is switched otherwise.
  ///
  /// - Parameters:
  ///   - outputs: The outputs' keys, such as `"relay1"`, or their labels, in any case.
  ///   - group: The group, or `nil` for the device's main group. Defaults to `nil`.
  /// - Returns: What was done. No level is reported.
  /// - Throws: ``DeviceControlError/noSuchOutput(_:group:product:)`` for an output the group
  ///   doesn't have, ``DeviceControlError/outputsInactive(group:product:)`` when the flag isn't
  ///   in its state, the other ``DeviceControlError`` refusals of ``turnOn(level:group:)``,
  ///   and the modem's errors.
  @discardableResult
  public func turnOn(outputs: [String], group: Int? = nil) async throws -> DeviceTurnOnResult {

    let number: Int = try await switchOutputs(outputs, group: group, action: DeviceControlModel.onAction, for: .turnOn)

    return DeviceTurnOnResult(group: number, level: nil, ignoredLevel: nil)

  }

  /// Turns some of a group's outputs off with its type's `off` action, as
  /// ``turnOn(outputs:group:)`` turns them on, and leaves the others as they are.
  ///
  /// - Parameters:
  ///   - outputs: The outputs' keys or labels.
  ///   - group: The group, or `nil` for the device's main group. Defaults to `nil`.
  /// - Throws: The errors of ``turnOn(outputs:group:)``.
  public func turnOff(outputs: [String], group: Int? = nil) async throws {

    _ = try await switchOutputs(outputs, group: group, action: DeviceControlModel.offAction, for: .turnOff)

  }

  /// Sends a group's action with the named outputs' bits ORed into its parameter, once the
  /// outputs are the load.
  ///
  /// - Returns: The group's number.
  private func switchOutputs(_ names: [String], group number: Int?, action name: SettingName, for operation: DeviceOperation) async throws -> Int {

    let model: DeviceControlModel = try await controlModel()
    let target: DeviceControlModel.Group = try controlGroup(number, in: model, for: operation)
    let groupNumber: Int = Int(target.number.rawValue)

    guard let action = target.type.action(named: name), action.value == nil else {

      throw DeviceControlError.unsupported(operation, product: model.product)

    }

    guard let outputs = target.type.outputs, !names.isEmpty else {

      throw DeviceControlError.noSuchOutput(names.first ?? "", group: groupNumber, product: model.product)

    }

    var mask: UInt8 = 0

    for name in names {

      let wanted: String = name.lowercased()

      guard let output = outputs.bits.first(where: { (output: GroupType.Outputs.Output) -> Bool in

        output.name.rawValue.lowercased() == wanted || output.label.lowercased() == wanted

      }) else {

        throw DeviceControlError.noSuchOutput(name, group: groupNumber, product: model.product)

      }

      mask |= output.mask

    }

    let message: DeviceControlModel.ActionMessage = try model.message(for: action, of: target, value: mask, to: address)

    guard model.canAddress(target, with: name) else {

      throw DeviceControlError.unaddressable(operation, group: groupNumber, product: model.product)

    }

    if let condition = outputs.activeWhen {

      guard let flag = model.commandSet?.operatingFlag(named: condition.flag) else {

        throw DeviceControlError.outputsInactive(group: groupNumber, product: model.product)

      }

      let reply: ReceivedMessage = try await request(StandardMessage(to: address, command: flag.readCommand), timeout: network.requestTimeout, for: .control(operation))

      guard flag.isSet(in: reply) == condition.isSet else {

        throw DeviceControlError.outputsInactive(group: groupNumber, product: model.product)

      }

    }

    try await send(message, for: operation)

    // The level isn't the outputs' mask, so only that the device answered is recorded.
    await network.recordAnswer(of: address, level: nil)

    return groupNumber

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

    _ = try await request(StandardMessage(to: address, command: command), timeout: network.requestTimeout, for: .control(.turnOnFast))

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

    _ = try await request(StandardMessage(to: address, command: command), timeout: network.requestTimeout, for: .control(.turnOffFast))

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

    _ = try await request(StandardMessage(to: address, command: command), timeout: network.requestTimeout, for: .control(.instantChange))

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

    let acknowledgment: ReceivedMessage = try await request(
      StandardMessage(to: address, command: try command.command()),
      timeout: network.requestTimeout,
      for: .control(.status)
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

    _ = try await request(StandardMessage(to: address, command: StandardDirectCommand.ping), timeout: network.requestTimeout, for: .control(.status))

    await network.recordAnswer(of: address, level: nil)

  }

  /// Makes the device beep.
  ///
  /// Beep is harmless, and the catalog doesn't list it for every device that beeps, so it's
  /// sent whatever the catalog says: the Beep the device's command set lists, or else the one
  /// the Insteon protocol defines, even to a device whose identity isn't known. The result
  /// says whether the command set lists it. A Beep the catalog marks as never sent, or whose
  /// bytes are ones never sent to the device, such as Set Operating Flags that turns the radio
  /// off, isn't sent.
  ///
  /// - Returns: Whether the device's command set lists Beep.
  /// - Throws: ``DeviceControlError/unsupported(_:product:)`` for a Beep that's never sent;
  ///   the modem's errors, such as `ModemError.deviceRejected` from a device that
  ///   isn't linked to the modem, and the errors of the modem and the connection to it while
  ///   the device is asked for its identity.
  @discardableResult
  public func beep() async throws -> DeviceBeepResult {

    let description: DeviceDescription?

    do {

      description = try await deviceDescription()

    } catch DeviceControlError.notLinked {

      // Beep is sent anyway, and the device's answer says why it didn't beep.
      description = nil

    }

    let commands: CommandSet? = description?.commandSet
    let listed: DeviceStandardCommand? = commands?.standardCommand(named: Self.beepCommand)
    let command: Command

    // A Beep the catalog lists but never sends isn't sent, nor is the protocol's in its place.
    if let description, let commands, listed != nil, Self.sendableBeep(in: commands) == nil {

      throw DeviceControlError.unsupported(.beep, product: DeviceControlModel.product(of: description))

    }

    if let listed {

      command = try listed.command()

    } else {

      command = StandardDirectCommand.beep.command

    }

    _ = try await request(StandardMessage(to: address, command: command), timeout: network.requestTimeout, for: .control(.beep))

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
  /// Some settings are never written: turning off the device's radio or powerline, and
  /// requiring a checksum in every message, any of which can cut the device off from the
  /// modem, and any other flag the catalog guards with `FlagGuard.keep`. The programming lock,
  /// and any flag the catalog guards with `FlagGuard.neverSet`, is only turned off, never on,
  /// so a device is never left locked. A command the catalog guards with `CommandGuard.never`
  /// is never sent, nor is a Set Operating Flags command with the same bytes. All of these are
  /// refused before anything is sent, and the radio, powerline, checksum and programming lock
  /// flags are refused even when the catalog gives no guard. A value whose byte holds
  /// operating flags, which the catalog marks with `SettingValue.flagsQuery`, such as an
  /// open/close sensor's configuration byte, is refused before it's written when it would set
  /// a bit that's never set, or change a bit that's kept; the device is asked for the byte
  /// first, to compare. The guarded bits of an extended command's flags parameter are checked
  /// the same way.
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
  ///   ``DeviceSettingError/neverWritten(label:)`` or
  ///   ``DeviceSettingError/leavesProgrammingLocked(label:)`` for a setting that isn't written,
  ///   or ``DeviceSettingError/notChanged(title:requested:reported:)`` when the device reports
  ///   another value afterward; ``DeviceControlError/noSuchGroup(_:product:)`` for a button
  ///   that isn't a group number; and the modem's errors.
  public func writeSetting(_ key: String, to text: String, button: Int? = nil) async throws -> DeviceSettingChange {

    let (description, commands): (DeviceDescription, CommandSet) = try await describedSettings()

    guard let item = commands.settingItem(named: key) else {

      throw DeviceSettingError.noSuchSetting(key, product: DeviceControlModel.product(of: description))

    }

    // Refused before anything is sent, whatever the catalog says about writing it.
    if DeviceSettingSafety.isNeverWritten(item, in: commands) {

      throw DeviceSettingError.neverWritten(label: item.label)

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

  // MARK: - Sending

  /// What a message is sent for, which says how a refusal to send it is reported.
  private enum SendPurpose {

    /// An operation, refused with ``DeviceControlError/unsupported(_:product:)``.
    case control(DeviceOperation)

    /// Writing a setting, refused with ``DeviceSettingError/neverWritten(label:)``.
    case setting(label: String)

    /// A message sent as it's given, through a raw passthrough, refused with the
    /// ``SendRefusal`` itself.
    case asGiven

    /// Whether the message's bytes are sent as they're given, rather than built and checked
    /// against what the device reported, so any guarded flag in a byte it writes refuses it.
    var sendsBytesAsGiven: Bool {

      switch self {
      case .asGiven, .control(.keepAwake):
        return true
      case .control, .setting:
        return false
      }

    }

  }

  /// Sends a message the catalog's linking from a Hub names, such as the one that keeps a
  /// battery-powered device awake while it links, through the same guards as every other
  /// message the device is sent.
  ///
  /// A command set entry gives the bytes: a flag command, or a standard or extended command,
  /// with `duration`'s whole seconds, or else its parameter's largest value, for a parameter;
  /// or an operating flag, set or cleared with Set Operating Flags in the form the device takes.
  /// A message given by its bytes is sent as given. Nothing else is written: no other flag,
  /// and never one the catalog or the floor guards, nor a command the catalog never sends.
  ///
  /// - Parameters:
  ///   - message: The message.
  ///   - duration: How long the message keeps the device awake, if the catalog says.
  ///   - writableFlags: The operating flags a linking flow may write.
  /// - Throws: ``DeviceControlError/unsupported(_:product:)`` for a message that's never
  ///   sent, ``DeviceControlError/missingCommand(_:product:)`` for one the command set
  ///   doesn't describe, `FieldError` for a parameter that doesn't fit, and the modem's
  ///   errors.
  func sendLinkingMessage(_ message: DeviceLifecycle.HubLinking.HubMessage, duration: Duration?, writableFlags: Set<SettingName>) async throws {

    let description: DeviceDescription? = await network.registry.device(address)?.deviceDescription
    let commands: CommandSet? = description?.commandSet
    let product: String = description.map { (described: DeviceDescription) -> String in DeviceControlModel.product(of: described) } ?? "this device"
    let refused = DeviceControlError.unsupported(.keepAwake, product: product)
    let purpose: SendPurpose = .control(.keepAwake)

    // A linking flow writes only the flags the catalog lets it. The registry can change while
    // a device links, so a flag outside them is refused rather than asserted.
    if let written = DeviceLinkingCoordinator.flagWritten(by: message, in: commands) {

      guard writableFlags.contains(written) else {

        throw refused

      }

    }

    switch message {
    case let .bytes(raw):
      if raw.isExtended {

        // A message given by its bytes never writes the device's extended settings: which
        // bits they hold is the command set's to say, through a command it names.
        if raw.command == Command(command1: 0x2E, command2: 0x00), raw.fixedBytes.contains(where: { (byte: FixedUserDataByte) -> Bool in byte.position == 2 && byte.value != 0x00 }) {

          throw refused

        }

        var userData = UserData()

        for byte in raw.fixedBytes {

          userData[byte.position] = byte.value

        }

        _ = try await request(ExtendedMessage(to: address, command: raw.command, userData: userData, integrity: raw.integrity.scheme), timeout: Modem.defaultExtendedRequestTimeout, for: purpose)

      } else {

        _ = try await request(StandardMessage(to: address, command: raw.command), timeout: network.requestTimeout, for: purpose)

      }

    case let .flag(condition):
      guard let commands, let description, let flag = commands.operatingFlag(named: condition.flag) else {

        throw DeviceControlError.missingCommand(condition.flag.rawValue, product: product)

      }

      // A kept flag is never written, and a never-set flag is only cleared.
      switch DeviceSettingSafety.rule(for: flag) {
      case .keep?:
        throw refused
      case .neverSet? where condition.isSet:
        throw refused
      default:
        break
      }

      guard let change = commands.change(for: flag, setting: condition.isSet), !DeviceSettingSafety.sendsNeverSentCommand(change, in: commands) else {

        throw refused

      }

      switch change {
      case let .setOperatingFlags(command2):
        try await sendSetOperatingFlags(command2, extendedWhen: flag.extendedWhen, description: description, commands: commands, purpose: purpose)
      case let .standardCommand(command):
        _ = try await request(StandardMessage(to: address, command: try command.command()), timeout: network.requestTimeout, for: purpose)
      }

    case let .command(name):
      guard let commands, let description else {

        throw DeviceControlError.missingCommand(name.rawValue, product: product)

      }

      if let flagCommand = commands.flagCommands.first(where: { (entry: OperatingFlagCommand) -> Bool in entry.name == name }) {

        guard !DeviceSettingSafety.isNeverSent(flagCommand.sendGuard), !DeviceSettingSafety.neverSentNames.contains(name) else {

          throw refused

        }

        try await sendSetOperatingFlags(
          flagCommand.command.command.command2,
          extendedWhen: flagCommand.extendedWhen,
          description: description,
          commands: commands,
          purpose: purpose
        )

      } else if let standard = commands.standardCommand(named: name) {

        guard DeviceSettingSafety.isSendable(standard, in: commands) else {

          throw refused

        }

        let command: Command

        switch standard.command2 {
        case .fixed:
          command = try standard.command()
        case let .parameter(field):
          command = try standard.command(Self.durationValue(duration, for: field))
        }

        _ = try await request(StandardMessage(to: address, command: command), timeout: network.requestTimeout, for: purpose)

      } else if let extended = commands.extendedCommand(named: name) {

        guard DeviceSettingSafety.isSendable(extended, in: commands) else {

          throw refused

        }

        let takesDuration: MessageField? = Self.durationParameter(of: extended)
        var values: [SettingName: FieldValue] = [:]

        // Only the parameter that takes the duration gets it; any other is zero.
        for parameter in extended.parameters {

          values[parameter.name] = parameter == takesDuration ? Self.durationValue(duration, for: parameter) : Self.zeroValue(for: parameter)

        }

        _ = try await request(try extended.message(to: address, values: values), timeout: Modem.defaultExtendedRequestTimeout, for: purpose)

      } else {

        throw DeviceControlError.missingCommand(name.rawValue, product: product)

      }
    }

    await network.recordAnswer(of: address, level: nil)

  }

  /// Refuses to keep a device awake when the message that lets it sleep again is never sent
  /// to it, so it isn't left awake, draining its batteries: a ``ProtectedCommand`` its
  /// command set doesn't name, or bytes its command set never sends.
  ///
  /// - Parameter keepAwake: How the catalog keeps the device awake.
  /// - Throws: ``DeviceControlError/unsupported(_:product:)`` when the release is never sent.
  func refuseKeepAwakeWithoutRelease(_ keepAwake: DeviceLifecycle.HubLinking.KeepAwake) async throws {

    guard let release = keepAwake.release else {

      return

    }

    let description: DeviceDescription? = await network.registry.device(address)?.deviceDescription
    let commands: CommandSet? = description?.commandSet

    guard let command = Self.command(of: release, in: commands), DeviceSettingSafety.isNeverSent(command, in: commands) else {

      return

    }

    throw DeviceControlError.unsupported(.keepAwake, product: description.map { (described: DeviceDescription) -> String in DeviceControlModel.product(of: described) } ?? "this device")

  }

  /// The cmd1 and cmd2 a message the catalog's linking from a Hub names sends, when its bytes
  /// or the command set say what they are.
  static func command(of message: DeviceLifecycle.HubLinking.HubMessage, in commands: CommandSet?) -> Command? {

    switch message {
    case let .bytes(raw):
      return raw.command
    case let .flag(condition):
      guard let commands, let flag = commands.operatingFlag(named: condition.flag), let change = commands.change(for: flag, setting: condition.isSet) else {

        return nil

      }

      switch change {
      case let .setOperatingFlags(command2):
        return Command(command1: DeviceSettingSafety.setOperatingFlagsCommand1, command2: command2)
      case let .standardCommand(standard):
        return try? standard.command()
      }
    case let .command(name):
      if let flagCommand = commands?.flagCommands.first(where: { (entry: OperatingFlagCommand) -> Bool in entry.name == name }) {

        return flagCommand.command.command

      }

      if let standard = commands?.standardCommand(named: name), case let .fixed(command2) = standard.command2 {

        return Command(command1: standard.command1, command2: command2)

      }

      return commands?.extendedCommand(named: name)?.command
    }

  }

  /// Sends a message as it's given, through the guards every message the device is sent
  /// passes, then collects the other messages the device sends for a time.
  ///
  /// - Parameters:
  ///   - message: The message, whose ``DirectMessage/device`` is the device.
  ///   - duration: How long to collect what the device sends after its acknowledgment.
  ///   - onAcknowledgment: Called with the device's acknowledgment.
  /// - Returns: The other messages from the device, in order.
  /// - Throws: ``SendRefusal`` before anything is sent, and the modem's errors.
  func sendAsGiven(_ message: DirectMessage, collectingFor duration: Duration, onAcknowledgment: (ReceivedFrame) -> Void) async throws -> [ReceivedFrame] {

    let device: InsteonAddress = address
    let replies: AsyncStream<ModemReply> = await modem.replies()
    let acknowledgment: ReceivedMessage

    if let extended = message.extended {

      acknowledgment = try await request(extended, timeout: Modem.defaultExtendedRequestTimeout, for: .asGiven)

    } else {

      acknowledgment = try await request(StandardMessage(to: device, command: message.command), timeout: network.requestTimeout, for: .asGiven)

    }

    onAcknowledgment(ReceivedFrame(acknowledgment))

    let received: [ModemReply] = await ModemSession.collect(replies, within: duration, clock: network.clock)
    var skippedAcknowledgment = false
    var frames: [ReceivedFrame] = []

    for reply in received {

      guard case let .messageReceived(incoming) = reply, incoming.sender == device else {

        continue

      }

      // The acknowledgment comes through the stream too.
      if !skippedAcknowledgment, incoming == acknowledgment {

        skippedAcknowledgment = true
        continue

      }

      frames.append(ReceivedFrame(incoming))

    }

    return frames

  }

  /// The parameter of a keep-awake extended command that takes how long to stay awake: the
  /// one in seconds, or else its only number, or `nil` when neither says.
  static func durationParameter(of command: DeviceExtendedCommand) -> MessageField? {

    let numbers: [MessageField] = command.parameters.filter { (field: MessageField) -> Bool in

      if case .number = field.kind {

        return true

      }

      return false

    }

    let seconds: MessageField? = numbers.first { (field: MessageField) -> Bool in

      if case let .number(_, _, unit) = field.kind, unit == .seconds {

        return true

      }

      return false

    }

    return seconds ?? (numbers.count == 1 ? numbers[0] : nil)

  }

  /// A parameter's value whose bits are all zero, for a parameter a keep-awake message leaves
  /// as it is.
  static func zeroValue(for field: MessageField) -> FieldValue {

    switch field.kind {
    case .number:
      return .number(0)
    case .buttons:
      return .buttons([])
    case .enumeration:
      return .unnamed(0)
    case .flags:
      return .flags([])
    case .boolean:
      return .boolean(false)
    }

  }

  /// The value of a keep-awake command's parameter: `duration`'s whole seconds, or else the
  /// parameter's largest value, kept within the parameter's range.
  static func durationValue(_ duration: Duration?, for field: MessageField) -> FieldValue {

    let range: ClosedRange<Double> = field.range ?? 0...255
    let seconds: Double = duration.map { (duration: Duration) -> Double in Double(duration.components.seconds) } ?? range.upperBound

    return .number(min(max(seconds, range.lowerBound), range.upperBound))

  }

  /// The command set's Beep, if the device may be sent it.
  static func sendableBeep(in commands: CommandSet) -> DeviceStandardCommand? {

    guard let beep = commands.standardCommand(named: beepCommand), DeviceSettingSafety.isSendable(beep, in: commands) else {

      return nil

    }

    return beep

  }

  /// Refuses a message whose bytes are never sent to the device, as
  /// `DeviceSettingSafety.isNeverSent(_:in:)` says from its command set: Poke, a
  /// ``ProtectedCommand`` the command set doesn't name for a flag it doesn't guard, and the
  /// bytes the catalog's guards add; and, for a
  /// message sent as it's given, an extended message that writes a byte holding a guarded
  /// flag, as `DeviceSettingSafety.guardedFlagWritten(by:userData:in:)` finds it. Every
  /// message the device is sent is checked here, with the bytes it actually carries, so a
  /// command filled in with a value, or listed under another name, can't send them.
  private func refuseIfNeverSent(_ command: Command, userData: UserData? = nil, for purpose: SendPurpose) async throws {

    let description: DeviceDescription? = await network.registry.device(address)?.deviceDescription
    let commands: CommandSet? = description?.commandSet
    let product: String = description.map { (described: DeviceDescription) -> String in DeviceControlModel.product(of: described) } ?? "this device"
    let refusal: SendRefusal

    let isNeverSent: Bool = DeviceSettingSafety.isNeverSent(command, in: commands)

    if isNeverSent, let protected = ProtectedCommand(command) {

      refusal = .protected(protected)

    } else if isNeverSent {

      refusal = .neverSentToDevice(product: product)

    } else if purpose.sendsBytesAsGiven, let userData, let commands, let label = DeviceSettingSafety.guardedFlagWritten(by: command, userData: userData, in: commands) {

      refusal = .writesGuardedFlags(label: label)

    } else {

      return

    }

    switch purpose {
    case let .control(operation):
      throw DeviceControlError.unsupported(operation, product: product)
    case let .setting(label):
      throw DeviceSettingError.neverWritten(label: label)
    case .asGiven:
      throw refusal
    }

  }

  /// Sends a standard message once ``refuseIfNeverSent(_:userData:for:)`` allows it. Every
  /// standard message the device is sent goes through here.
  private func request(_ message: StandardMessage, timeout: Duration, for purpose: SendPurpose) async throws -> ReceivedMessage {

    try await refuseIfNeverSent(message.command, for: purpose)

    return try await modem.request(message, timeout: timeout)

  }

  /// Sends an extended message once ``refuseIfNeverSent(_:userData:for:)`` allows it, by its
  /// cmd1, cmd2 and user data. Every extended message the device is sent goes through here.
  private func request(_ message: ExtendedMessage, timeout: Duration, for purpose: SendPurpose) async throws -> ReceivedMessage {

    try await refuseIfNeverSent(message.command, userData: message.userData, for: purpose)

    return try await modem.request(message, timeout: timeout)

  }

  /// Sends an action's message, a standard one with the network's timeout and an extended one
  /// with the timeout for extended requests.
  private func send(_ message: DeviceControlModel.ActionMessage, for operation: DeviceOperation) async throws {

    switch message {
    case let .standard(standard):
      _ = try await request(standard, timeout: network.requestTimeout, for: .control(operation))
    case let .extended(extended):
      _ = try await request(extended, timeout: Modem.defaultExtendedRequestTimeout, for: .control(operation))
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

    guard let command = commands.standardCommand(named: name), DeviceSettingSafety.isSendable(command, in: commands) else {

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

    let acknowledgment: ReceivedMessage = try await request(
      StandardMessage(to: address, command: StandardDirectCommand.statusRequest()),
      timeout: network.requestTimeout,
      for: .control(.status)
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
  /// - Returns: For a state whose catalog entry gives the bits that mean on, whether they match;
  ///   for a state with a bit per group, the group's bit as on or off; for a group that
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

    // A reply whose bits carry more than the group's state, such as an EZFlora's valve status,
    // is on only when the bits the catalog names match.
    if let onWhen = state.onWhen {

      let isOn: Bool = onWhen.isOn(command2: value)

      return (.onOff(isOn), isOn)

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

      return try await request(message, timeout: network.requestTimeout, for: .control(.settings))

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

    try await refuseIfNeverSent(message.command, userData: message.userData, for: .control(.settings))

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
  private func sendFlag(_ command2: UInt8, flag: OperatingFlag, description: DeviceDescription, commands: CommandSet) async throws {

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
  private func sendSetOperatingFlags(
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
  private func engine(_ description: DeviceDescription) async throws -> InsteonEngine? {

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
