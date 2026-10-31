import InsteonDeviceCatalog
import InsteonProtocol

/// What a ``Device`` can be told to do and how to read its state, from the Insteon device
/// catalog's group types, or from the device's category when the catalog gives none.
///
/// Every decision a front end would otherwise make about a device, such as whether a level
/// means anything to it, is made here from this model.
struct DeviceControlModel: Sendable {

  /// One of the device's groups with the type that says how to control it.
  struct Group: Sendable {

    /// The group number.
    let number: AllLinkGroupNumber

    /// The group's name, such as `"Load"` or `"Top outlet"`.
    let name: String

    /// The group's type.
    let type: GroupType

  }

  /// Where the model came from.
  enum Source: Hashable, Sendable {

    /// The catalog's profile and command set for the device.
    case catalog

    /// The device's category, because the catalog gives no group types for the device.
    case categoryFallback

    /// Nothing: the device's identity isn't known, or neither the catalog nor its category
    /// says how to control it.
    case uncontrolled

  }

  /// The device's description, or `nil` if its identity isn't known.
  let description: DeviceDescription?

  /// Where the model came from.
  let source: Source

  /// The groups whose types the model knows, in the profile's order.
  let groups: [Group]

  /// The number of the group controlled when no group is given.
  let mainGroupNumber: AllLinkGroupNumber?

  /// The standard commands the group types' actions and states name.
  let standardCommands: [DeviceStandardCommand]

  /// The extended commands the group types' actions may name, such as a fan's speeds, sent
  /// with a group in D1.
  let extendedCommands: [DeviceExtendedCommand]

  /// The device's command set, if the catalog gives one.
  var commandSet: CommandSet? {

    description?.commandSet

  }

  /// The standard command with a name.
  func standardCommand(named name: SettingName) -> DeviceStandardCommand? {

    standardCommands.first { (command: DeviceStandardCommand) -> Bool in command.name == name }

  }

  /// The extended command with a name.
  func extendedCommand(named name: SettingName) -> DeviceExtendedCommand? {

    extendedCommands.first { (command: DeviceExtendedCommand) -> Bool in command.name == name }

  }

  /// The group with a number.
  func group(_ number: AllLinkGroupNumber) -> Group? {

    groups.first { (group: Group) -> Bool in group.number == number }

  }

  /// The main group, if any.
  var mainGroup: Group? {

    mainGroupNumber.flatMap { (number: AllLinkGroupNumber) -> Group? in group(number) }

  }

  /// The product as a sentence names it: the catalog's display name, or else the identity.
  var product: String {

    guard let description else {

      return "this device"

    }

    return Self.product(of: description)

  }

  /// A product as a sentence names it: the catalog's display name, such as
  /// `"Dimmer Switch 2477D (SwitchLinc Dimmer)"`, or else its identity, such as
  /// `"category 0x07, subcategory 0x1A"`.
  static func product(of description: DeviceDescription) -> String {

    description.displayName ?? "category \(description.category), subcategory \(description.subcategory)"

  }

  // MARK: - Messages

  /// A message an action sends: a standard one, or an extended one with its user data and
  /// integrity bytes.
  enum ActionMessage: Hashable, Sendable {

    /// A standard direct message.
    case standard(StandardMessage)

    /// An extended direct message.
    case extended(ExtendedMessage)

    /// The message's cmd1 and cmd2.
    var command: Command {

      switch self {
      case let .standard(message):
        message.command
      case let .extended(message):
        message.command
      }

    }

  }

  /// The message an action of a group sends, from the standard or extended command it names.
  ///
  /// A command that takes a value in cmd2 gets the action's value, or else `value`. An
  /// extended command gets its fixed user data bytes, the group in D1 when it's per button,
  /// and its integrity bytes.
  ///
  /// - Parameters:
  ///   - action: The action.
  ///   - group: The group.
  ///   - value: The value for cmd2 when the action leaves it to the caller.
  ///   - device: The device to send it to.
  /// - Returns: The message.
  /// - Throws: ``DeviceControlError/missingCommand(_:product:)`` when the command set describes
  ///   no command by the action's name that can be sent, and `FieldError` for a value that
  ///   doesn't fit.
  func message(for action: GroupType.Action, of group: Group, value: UInt8, to device: InsteonAddress) throws -> ActionMessage {

    let byte: UInt8 = action.value ?? value

    if let command = standardCommand(named: action.command) {

      switch command.command2 {
      case .fixed:
        return .standard(StandardMessage(to: device, command: try command.command()))
      case .parameter:
        return .standard(StandardMessage(to: device, command: try command.command(.unnamed(Int(byte)))))
      }

    }

    if let command = extendedCommand(named: action.command), let userData = Self.userData(of: command, group: group) {

      let takesValue: Bool = Self.takesValueInCommand2(command)
      let bytes = Command(command1: command.command.command1, command2: takesValue ? byte : command.command.command2)

      return .extended(ExtendedMessage(to: device, command: bytes, userData: userData, integrity: command.integrity.scheme))

    }

    throw DeviceControlError.missingCommand(action.command.rawValue, product: product)

  }

  /// An extended command's user data for a group, before its integrity bytes: its fixed bytes,
  /// and the group in D1 when it's per button; or `nil` when it takes a value in its user
  /// data, which an action doesn't give.
  static func userData(of command: DeviceExtendedCommand, group: Group) -> UserData? {

    guard command.parameters.allSatisfy({ (field: MessageField) -> Bool in field.location == .command2 }) else {

      return nil

    }

    var userData = UserData()

    for byte in command.fixedBytes {

      userData[byte.position] = byte.value

    }

    if command.isPerButton {

      userData[1] = group.number.rawValue

    }

    return userData

  }

  /// Whether an extended command takes a value in cmd2.
  static func takesValueInCommand2(_ command: DeviceExtendedCommand) -> Bool {

    command.parameters.contains { (field: MessageField) -> Bool in field.location == .command2 }

  }

  /// An address that stands for the device when messages are compared, since every message
  /// compared goes to the same device.
  private static let comparedDevice = InsteonAddress(0x00, 0x00, 0x00)

  // MARK: - Capabilities of a group

  /// Whether an action of a group sends a message that reaches the group: the group is the
  /// main group, or no other group's action of the same name sends the same message.
  ///
  /// A KeypadLinc's detached load, whose `on` action names Light On without a group, sends
  /// the main group's message, so it can't be reached on its own.
  func canAddress(_ group: Group, with name: SettingName) -> Bool {

    guard
      let action = group.type.action(named: name),
      let sent = try? message(for: action, of: group, value: 0xFF, to: Self.comparedDevice)
    else {

      return false

    }

    if group.number == mainGroupNumber {

      return true

    }

    return !groups.contains { (other: Group) -> Bool in

      guard other.number != group.number, let otherAction = other.type.action(named: name) else {

        return false

      }

      return (try? message(for: otherAction, of: other, value: 0xFF, to: Self.comparedDevice)) == sent

    }

  }

  /// Whether a group's On takes a level: its `on` action leaves the value to the caller, the
  /// command it names takes one in cmd2, and the action reaches the group.
  func canDim(_ group: Group) -> Bool {

    guard let on = group.type.action(named: Self.onAction), on.value == nil, canAddress(group, with: Self.onAction) else {

      return false

    }

    if let command = standardCommand(named: on.command) {

      if case .parameter = command.command2 {

        return true

      }

      return false

    }

    if let command = extendedCommand(named: on.command) {

      return Self.takesValueInCommand2(command)

    }

    return false

  }

  /// Whether a group has both an `on` and an `off` action.
  func turnsOnAndOff(_ group: Group) -> Bool {

    group.type.action(named: Self.onAction) != nil && group.type.action(named: Self.offAction) != nil

  }

  /// Whether a group can be turned on and off: it has both actions, and each sends a message
  /// that reaches it.
  func canTurnOnAndOff(_ group: Group) -> Bool {

    turnsOnAndOff(group) && canAddress(group, with: Self.onAction) && canAddress(group, with: Self.offAction)

  }

  /// Whether a group's state can be read as its type says: its state command is a standard
  /// command the command set describes, and its reply is about the group. A reply with a bit
  /// per group is about groups 1 through 8; any other reply is about the main group, or about
  /// a group whose state command no other group's state shares.
  func canRead(_ group: Group) -> Bool {

    guard
      let state = group.type.state,
      let command = standardCommand(named: state.command),
      let sent = try? command.command()
    else {

      return false

    }

    if state.isBitPerGroup {

      return (1...8).contains(Int(group.number.rawValue))

    }

    if group.number == mainGroupNumber {

      return true

    }

    return !groups.contains { (other: Group) -> Bool in

      guard
        other.number != group.number,
        let otherState = other.type.state,
        !otherState.isBitPerGroup,
        let otherCommand = standardCommand(named: otherState.command)
      else {

        return false

      }

      return (try? otherCommand.command()) == sent

    }

  }

  /// Whether a status request for the group reports the device's level, as
  /// ``NetworkDeviceState/level`` holds it: the group is the main group, and its state is the
  /// whole acknowledgment of Light Status Request rather than one bit of it.
  func reportsDeviceLevel(_ group: Group) -> Bool {

    guard group.number == mainGroupNumber, let state = group.type.state, !state.isBitPerGroup, let command = standardCommand(named: state.command) else {

      return false

    }

    return (try? command.command()) == StandardDirectCommand.statusRequest().command

  }

  // MARK: - Building

  /// The name of the action that turns a group on.
  static let onAction: SettingName = "on"

  /// The name of the action that turns a group off.
  static let offAction: SettingName = "off"

  /// The model for a device, from its description.
  ///
  /// - Parameter description: The device's description, or `nil` if its identity isn't known.
  /// - Returns: The catalog's group types when the profile gives any; or else, for a device
  ///   whose category is dimmable lighting control or switched lighting control, one group
  ///   that dims or switches, as `GroupType.Kind.fallback(for:)` says; or else no groups.
  static func make(_ description: DeviceDescription?) -> DeviceControlModel {

    guard let description else {

      return DeviceControlModel(description: nil, source: .uncontrolled, groups: [], mainGroupNumber: nil, standardCommands: [], extendedCommands: [])

    }

    var groups: [Group] = []

    for group in description.profile?.groups ?? [] {

      guard let type = description.groupType(forGroup: group.number), !groups.contains(where: { $0.number == group.number }) else {

        continue

      }

      groups.append(Group(number: group.number, name: group.name, type: type))

    }

    if !groups.isEmpty {

      let main: AllLinkGroupNumber = description.mainGroup?.number ?? groups[0].number

      return DeviceControlModel(
        description: description,
        source: .catalog,
        groups: groups,
        mainGroupNumber: main,
        // A command the catalog marks as never sent isn't one an action can send.
        standardCommands: (description.commandSet?.standardCommands ?? []).filter { (command: DeviceStandardCommand) -> Bool in

          DeviceSettingSafety.isSendable(command, in: description.commandSet)

        },
        extendedCommands: (description.commandSet?.extendedCommands ?? []).filter { (command: DeviceExtendedCommand) -> Bool in

          DeviceSettingSafety.isSendable(command, in: description.commandSet)

        }
      )

    }

    guard let kind = GroupType.Kind.fallback(for: description.category) else {

      return DeviceControlModel(description: description, source: .uncontrolled, groups: [], mainGroupNumber: nil, standardCommands: [], extendedCommands: [])

    }

    let isDimmer: Bool = kind == .dimmer
    let type: GroupType = isDimmer ? Fallback.dimmer : Fallback.relay
    let group = Group(number: 1, name: type.label, type: type)

    return DeviceControlModel(
      description: description,
      source: .categoryFallback,
      groups: [group],
      mainGroupNumber: group.number,
      standardCommands: isDimmer ? Fallback.dimmerCommands : Fallback.relayCommands,
      extendedCommands: []
    )

  }

}

/// The group types and commands a device gets from its category when the catalog gives none,
/// as the Insteon Developer's Guide gives them for lighting control.
private enum Fallback {

  static let lightOn: SettingName = "lightOn"

  static let lightOff: SettingName = "lightOff"

  static let readStatus: SettingName = "readStatus"

  /// Light On, with the level in cmd2.
  static let lightOnCommand = DeviceStandardCommand(
    name: lightOn,
    summary: "Turns the load on to the level in cmd2.",
    command1: StandardDirectCommand.on(level: 0xFF).command.command1,
    command2: .parameter(MessageField(name: "onLevel", summary: "The level to go to.", location: .command2, range: 0...255))
  )

  /// Light Off.
  static let lightOffCommand = DeviceStandardCommand(
    name: lightOff,
    summary: "Turns the load off.",
    command1: StandardDirectCommand.off.command.command1,
    command2: .fixed(StandardDirectCommand.off.command.command2)
  )

  /// Light Status Request, whose acknowledgment carries the level in cmd2.
  static func readStatusCommand(reply: MessageField) -> DeviceStandardCommand {

    DeviceStandardCommand(
      name: readStatus,
      summary: "Reads the load's level.",
      command1: StandardDirectCommand.statusRequest().command.command1,
      command2: .fixed(StandardDirectCommand.statusRequest().command.command2),
      reply: reply
    )

  }

  static let dimmerCommands: [DeviceStandardCommand] = [
    lightOnCommand,
    lightOffCommand,
    readStatusCommand(reply: MessageField(
      name: "onLevel",
      summary: "The load's level.",
      location: .command2,
      kind: .number(isSigned: false, scale: 100.0 / 255.0, unit: .percent)
    ))
  ]

  static let relayCommands: [DeviceStandardCommand] = [
    lightOnCommand,
    lightOffCommand,
    readStatusCommand(reply: MessageField(name: "onLevel", summary: "0x00 when off.", location: .command2))
  ]

  /// A load that dims.
  static let dimmer = GroupType(
    name: "light",
    label: "Light",
    kind: .dimmer,
    state: GroupType.State(command: readStatus),
    actions: [
      GroupType.Action(name: DeviceControlModel.onAction, label: "On", command: lightOn),
      GroupType.Action(name: DeviceControlModel.offAction, label: "Off", command: lightOff)
    ]
  )

  /// A load switched on and off.
  static let relay = GroupType(
    name: "load",
    label: "Load",
    kind: .relay,
    state: GroupType.State(
      command: readStatus,
      ranges: [
        GroupType.State.Range(values: 0x00...0x00, label: "Off"),
        GroupType.State.Range(values: 0x01...0xFF, label: "On")
      ]
    ),
    actions: [
      GroupType.Action(name: DeviceControlModel.onAction, label: "On", command: lightOn, value: 0xFF),
      GroupType.Action(name: DeviceControlModel.offAction, label: "Off", command: lightOff)
    ]
  )

}
