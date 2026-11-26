import InsteonDeviceCatalog
import InsteonProtocol

/// The catalog of the demo network: two invented products that no real device matches.
enum DemoCatalog {

  static let dimmerIdentity = ReportedIdentity(category: 0x01, subcategory: 0x7C, firmwareVersion: 0x45)

  static let relayIdentity = ReportedIdentity(category: 0x02, subcategory: 0x7D, firmwareVersion: 0x45)

  private static let lightOn = DeviceStandardCommand(
    name: "lightOn",
    summary: "Turns the load on to the level in cmd2.",
    command1: 0x11,
    command2: .parameter(MessageField(name: "onLevel", summary: "The level.", location: .command2, range: 0...255)),
    effect: .actuation, isIdempotent: true
  )

  private static let lightOff = DeviceStandardCommand(name: "lightOff", summary: "Turns the load off.", command1: 0x13, command2: .fixed(0x00), effect: .actuation, isIdempotent: true)

  private static let readLevel = DeviceStandardCommand(
    name: "readStatus",
    summary: "Reads the load's level.",
    command1: 0x19,
    command2: .fixed(0x00),
    reply: MessageField(name: "onLevel", summary: "The level.", location: .command2, kind: .number(scale: 0.392157, unit: .percent)),
    effect: .readOnly, isIdempotent: true
  )

  private static let readOnOff = DeviceStandardCommand(
    name: "readStatus",
    summary: "Reads whether the load is on.",
    command1: 0x19,
    command2: .fixed(0x00),
    reply: MessageField(name: "onLevel", summary: "0x00 when off.", location: .command2),
    effect: .readOnly, isIdempotent: true
  )

  private static let dimming = GroupType(
    name: "dimming",
    label: "Light",
    kind: .dimmer,
    state: GroupType.State(command: "readStatus"),
    actions: [
      GroupType.Action(name: "on", label: "On", command: "lightOn"),
      GroupType.Action(name: "off", label: "Off", command: "lightOff")
    ]
  )

  private static let switching = GroupType(
    name: "switching",
    label: "Load",
    kind: .relay,
    state: GroupType.State(
      command: "readStatus",
      ranges: [
        GroupType.State.Range(values: 0x00...0x00, label: "Off"),
        GroupType.State.Range(values: 0x01...0xFF, label: "On")
      ]
    ),
    actions: [
      GroupType.Action(name: "on", label: "On", command: "lightOn", value: 0xFF),
      GroupType.Action(name: "off", label: "Off", command: "lightOff")
    ]
  )

  private static let dimmerCommands = CommandSet(
    id: "demoDimmer",
    name: "Demo dimmer",
    summary: "A dimmer that turns on to a level and off.",
    standardCommands: [lightOn, lightOff, readLevel],
    groupTypes: [dimming]
  )

  private static let relayCommands = CommandSet(
    id: "demoRelay",
    name: "Demo relay",
    summary: "A relay that turns on and off.",
    standardCommands: [lightOn, lightOff, readOnOff],
    groupTypes: [switching]
  )

  private static func profile(model: String, name: String, identity: ReportedIdentity, commands: CommandSet, type: SettingName) -> DeviceProfile {

    DeviceProfile(
      model: ProductModel(rawValue: model),
      name: name,
      identities: [DeviceIdentity(category: identity.category, subcategory: identity.subcategory)],
      commandSets: [CommandSetEntry(commandSet: commands.id, category: identity.category, subcategory: identity.subcategory)],
      groups: [DeviceProfile.Group(number: 1, name: "Load", role: .both, type: type)]
    )

  }

  static let catalog = DeviceCatalog(
    profiles: [
      profile(model: "D100", name: "Demo Dimmer", identity: dimmerIdentity, commands: dimmerCommands, type: "dimming"),
      profile(model: "D200", name: "Demo Relay", identity: relayIdentity, commands: relayCommands, type: "switching")
    ],
    commandSets: [dimmerCommands, relayCommands]
  )

}
