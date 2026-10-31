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
    case none

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

  /// The device's command set, if the catalog gives one.
  var commandSet: CommandSet? {

    description?.commandSet

  }

  /// The standard command with a name.
  func standardCommand(named name: SettingName) -> DeviceStandardCommand? {

    standardCommands.first { (command: DeviceStandardCommand) -> Bool in command.name == name }

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

  // MARK: - Capabilities of a group

  /// Whether a group's On takes a level: its `on` action leaves the value to the caller, and
  /// the command it names takes one in cmd2.
  func canDim(_ group: Group) -> Bool {

    guard let on = group.type.action(named: Self.onAction), on.value == nil, let command = standardCommand(named: on.command) else {

      return false

    }

    if case .parameter = command.command2 {

      return true

    }

    return false

  }

  /// Whether a group has both an `on` and an `off` action.
  func turnsOnAndOff(_ group: Group) -> Bool {

    group.type.action(named: Self.onAction) != nil && group.type.action(named: Self.offAction) != nil

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

      return DeviceControlModel(description: nil, source: .none, groups: [], mainGroupNumber: nil, standardCommands: [])

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
        standardCommands: description.commandSet?.standardCommands ?? []
      )

    }

    guard let kind = GroupType.Kind.fallback(for: description.category) else {

      return DeviceControlModel(description: description, source: .none, groups: [], mainGroupNumber: nil, standardCommands: [])

    }

    let isDimmer: Bool = kind == .dimmer
    let type: GroupType = isDimmer ? Fallback.dimmer : Fallback.relay
    let group = Group(number: 1, name: type.label, type: type)

    return DeviceControlModel(
      description: description,
      source: .categoryFallback,
      groups: [group],
      mainGroupNumber: group.number,
      standardCommands: isDimmer ? Fallback.dimmerCommands : Fallback.relayCommands
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
