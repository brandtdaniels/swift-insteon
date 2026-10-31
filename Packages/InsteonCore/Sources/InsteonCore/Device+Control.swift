import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

// Turning the device's groups on and off, dimming them and reading their status.
extension Device {

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
  ///   ``info()``; and the modem's errors.
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
  ///   ``info()``; and the modem's errors.
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
  func switchOutputs(_ names: [String], group number: Int?, action name: SettingName, for operation: DeviceOperation) async throws -> Int {

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
  ///   the errors of ``info()``, and the modem's errors.
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
  ///   errors of ``info()``, and the modem's errors.
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
  ///   of ``turnOn(level:group:)``, the errors of ``info()``, and the modem's
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
  ///   ``info()``; and the modem's errors.
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
  func controlGroup(_ number: Int?, in model: DeviceControlModel, for operation: DeviceOperation) throws -> DeviceControlModel.Group {

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

}
