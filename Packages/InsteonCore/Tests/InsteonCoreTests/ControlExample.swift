import InsteonDeviceCatalog
import InsteonProtocol

/// A made-up catalog of devices to control: a dimmer with settings, a relay, a fan with a
/// light whose speeds are extended commands, a dual outlet whose outlets report one bit each
/// and whose second outlet takes an extended command with a checksum, and a keypad whose
/// detached load takes the main load's Light On.
enum ControlExample {

  // MARK: - Addresses

  static let dimmer = InsteonAddress(0x3A, 0x4B, 0x01)

  static let relay = InsteonAddress(0x3A, 0x4B, 0x02)

  static let fan = InsteonAddress(0x3A, 0x4B, 0x03)

  static let outlet = InsteonAddress(0x3A, 0x4B, 0x04)

  static let unknownDimmer = InsteonAddress(0x3A, 0x4B, 0x05)

  static let unknownRelay = InsteonAddress(0x3A, 0x4B, 0x06)

  static let unknownOther = InsteonAddress(0x3A, 0x4B, 0x07)

  static let unidentified = InsteonAddress(0x3A, 0x4B, 0x08)

  static let keypad = InsteonAddress(0x3A, 0x4B, 0x09)

  static let buttons = InsteonAddress(0x3A, 0x4B, 0x0A)

  static let guarded = InsteonAddress(0x3A, 0x4B, 0x0B)

  // MARK: - Identities

  static let dimmerIdentity = ReportedIdentity(category: 0x01, subcategory: 0x7C, firmwareVersion: 0x45)

  static let relayIdentity = ReportedIdentity(category: 0x02, subcategory: 0x7D, firmwareVersion: 0x45)

  static let fanIdentity = ReportedIdentity(category: 0x01, subcategory: 0x7E, firmwareVersion: 0x45)

  static let outletIdentity = ReportedIdentity(category: 0x02, subcategory: 0x7F, firmwareVersion: 0x45)

  static let unknownDimmerIdentity = ReportedIdentity(category: 0x01, subcategory: 0x55, firmwareVersion: 0x45)

  static let unknownRelayIdentity = ReportedIdentity(category: 0x02, subcategory: 0x55, firmwareVersion: 0x45)

  static let unknownOtherIdentity = ReportedIdentity(category: 0x07, subcategory: 0x55, firmwareVersion: 0x45)

  static let keypadIdentity = ReportedIdentity(category: 0x01, subcategory: 0x7B, firmwareVersion: 0x45)

  static let buttonsIdentity = ReportedIdentity(category: 0x01, subcategory: 0x79, firmwareVersion: 0x45)

  /// Not in ``identities``; tests of the guarded flags give it on its own.
  static let guardedIdentity = ReportedIdentity(category: 0x01, subcategory: 0x78, firmwareVersion: 0x45)

  /// Every device but the unidentified one, as a network's snapshot would hold them.
  static let identities: [InsteonAddress: ReportedIdentity] = [
    dimmer: dimmerIdentity,
    relay: relayIdentity,
    fan: fanIdentity,
    outlet: outletIdentity,
    unknownDimmer: unknownDimmerIdentity,
    unknownRelay: unknownRelayIdentity,
    unknownOther: unknownOtherIdentity,
    keypad: keypadIdentity,
    buttons: buttonsIdentity
  ]

  // MARK: - Commands

  static let lightOn = DeviceStandardCommand(
    name: "lightOn",
    summary: "Turns the load on to the level in cmd2.",
    command1: 0x11,
    command2: .parameter(MessageField(name: "onLevel", summary: "The level.", location: .command2, range: 0...255))
  )

  static let lightOff = DeviceStandardCommand(name: "lightOff", summary: "Turns the load off.", command1: 0x13, command2: .fixed(0x00))

  static let readLevel = DeviceStandardCommand(
    name: "readStatus",
    summary: "Reads the load's level.",
    command1: 0x19,
    command2: .fixed(0x00),
    reply: MessageField(name: "onLevel", summary: "The level.", location: .command2, kind: .number(scale: 0.392157, unit: .percent))
  )

  static let readOnOff = DeviceStandardCommand(
    name: "readStatus",
    summary: "Reads whether the load is on.",
    command1: 0x19,
    command2: .fixed(0x00),
    reply: MessageField(name: "onLevel", summary: "0x00 when off.", location: .command2)
  )

  static let beep = DeviceStandardCommand(name: "beep", summary: "Beeps.", command1: 0x30, command2: .fixed(0x00))

  static let lightOnFast = DeviceStandardCommand(
    name: "lightOnFast",
    summary: "Turns the load on to the level in cmd2 at once.",
    command1: 0x12,
    command2: .parameter(MessageField(name: "onLevel", summary: "The level.", location: .command2, range: 0...255))
  )

  static let lightOffFast = DeviceStandardCommand(name: "lightOffFast", summary: "Turns the load off at once.", command1: 0x14, command2: .fixed(0x00))

  static let instantChange = DeviceStandardCommand(
    name: "instantChange",
    summary: "Changes the load to the level in cmd2 at once.",
    command1: 0x21,
    command2: .parameter(MessageField(name: "onLevel", summary: "The level.", location: .command2, range: 0...255))
  )

  // MARK: - Group types

  static let light = GroupType(
    name: "light",
    label: "Light",
    kind: .dimmer,
    state: GroupType.State(command: "readStatus"),
    actions: [
      GroupType.Action(name: "on", label: "On", command: "lightOn"),
      GroupType.Action(name: "off", label: "Off", command: "lightOff")
    ]
  )

  static let load = GroupType(
    name: "load",
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

  // MARK: - Command sets

  static let dimmerCommands = CommandSet(
    id: "exampleDimmer",
    name: "Example dimmer",
    summary: "A dimmer with a key beep and a ramp rate.",
    operatingFlags: [
      OperatingFlag(
        name: "keyBeep",
        summary: "Beeps on every button press.",
        query: .operatingFlags,
        bit: 0x02,
        on: 0x0A,
        off: 0x0B,
        label: "Key beep",
        section: .buttons,
        defaultValue: false
      )
    ],
    extendedSettings: ExtendedSettings(
      isPerButton: false,
      values: [
        SettingValue(name: "rampRate", summary: "How fast the load ramps.", position: 7, label: "Ramp rate", section: .load, table: "rampRate"),
        SettingValue(name: "onLevel", summary: "The level a press turns on to.", position: 8, label: "On-level", section: .load, unit: .percent, scale: 0.392157)
      ],
      writes: [
        SettingWrite(name: "rampRate", summary: "Sets the ramp rate.", selector: 0x05, isPerButton: false, bytes: [SettingWrite.Byte(position: 3, value: "rampRate")]),
        SettingWrite(name: "onLevel", summary: "Sets the on-level.", selector: 0x06, isPerButton: false, bytes: [SettingWrite.Byte(position: 3, value: "onLevel")])
      ]
    ),
    standardCommands: [lightOn, lightOff, readLevel, beep, lightOnFast, lightOffFast, instantChange],
    groupTypes: [light],
    valueTables: [
      ValueTable(name: "rampRate", entries: [
        ValueTable.Entry(value: 0x1C, label: "0.5 s", duration: .milliseconds(500)),
        ValueTable.Entry(value: 0x1F, label: "0.1 s", duration: .milliseconds(100))
      ])
    ]
  )

  static let relayCommands = CommandSet(
    id: "exampleRelay",
    name: "Example relay",
    summary: "A relay without Beep.",
    standardCommands: [lightOn, lightOff, readOnOff],
    groupTypes: [load]
  )

  static let fanCommands = CommandSet(
    id: "exampleFan",
    name: "Example fan",
    summary: "A fan with a light, whose speeds are extended commands with the fan's group in D1.",
    standardCommands: [
      lightOn,
      lightOff,
      readLevel,
      DeviceStandardCommand(name: "readFanSpeed", summary: "Reads the fan speed.", command1: 0x19, command2: .fixed(0x03))
    ],
    extendedCommands: [
      DeviceExtendedCommand(
        name: "fanOff",
        summary: "Turns the fan off.",
        command: Command(command1: 0x13, command2: 0x00),
        fixedBytes: [FixedUserDataByte(position: 1, value: 0x02)]
      ),
      DeviceExtendedCommand(
        name: "fanHigh",
        summary: "Turns the fan to high.",
        command: Command(command1: 0x11, command2: 0xFF),
        fixedBytes: [FixedUserDataByte(position: 1, value: 0x02)]
      )
    ],
    groupTypes: [
      light,
      GroupType(
        name: "fan",
        label: "Fan",
        kind: .fan,
        state: GroupType.State(
          command: "readFanSpeed",
          ranges: [
            GroupType.State.Range(values: 0x00...0x00, label: "Off"),
            GroupType.State.Range(values: 0x01...0x7F, label: "Low"),
            GroupType.State.Range(values: 0x80...0xFE, label: "Medium"),
            GroupType.State.Range(values: 0xFF...0xFF, label: "High")
          ]
        ),
        actions: [
          GroupType.Action(name: "off", label: "Off", command: "fanOff"),
          GroupType.Action(name: "high", label: "High", command: "fanHigh")
        ]
      )
    ]
  )

  static let outletCommands = CommandSet(
    id: "exampleOutlet",
    name: "Example outlet",
    summary: "Two outlets that report one bit each.",
    standardCommands: [
      lightOn,
      lightOff,
      DeviceStandardCommand(
        name: "readOutlets",
        summary: "Reads which outlets are on.",
        command1: 0x19,
        command2: .fixed(0x01),
        reply: MessageField(
          name: "outlets",
          summary: "The outlets that are on.",
          location: .command2,
          kind: .flags([FieldBit(mask: 0x01, name: "topOn"), FieldBit(mask: 0x02, name: "bottomOn")])
        )
      )
    ],
    extendedCommands: [
      DeviceExtendedCommand(
        name: "bottomOn",
        summary: "Turns the bottom outlet on.",
        command: Command(command1: 0x11, command2: 0xFF),
        fixedBytes: [FixedUserDataByte(position: 1, value: 0x02)],
        integrity: .checksum
      ),
      DeviceExtendedCommand(
        name: "bottomOff",
        summary: "Turns the bottom outlet off.",
        command: Command(command1: 0x13, command2: 0x00),
        fixedBytes: [FixedUserDataByte(position: 1, value: 0x02)],
        integrity: .checksum
      )
    ],
    groupTypes: [
      GroupType(
        name: "top",
        label: "Outlet",
        kind: .relay,
        state: GroupType.State(command: "readOutlets", isBitPerGroup: true),
        actions: [
          GroupType.Action(name: "on", label: "On", command: "lightOn", value: 0xFF),
          GroupType.Action(name: "off", label: "Off", command: "lightOff")
        ]
      ),
      GroupType(
        name: "bottom",
        label: "Outlet",
        kind: .relay,
        state: GroupType.State(command: "readOutlets", isBitPerGroup: true),
        actions: [
          GroupType.Action(name: "on", label: "On", command: "bottomOn"),
          GroupType.Action(name: "off", label: "Off", command: "bottomOff")
        ]
      )
    ]
  )

  static let keypadCommands = CommandSet(
    id: "exampleKeypad",
    name: "Example keypad",
    summary: "A load on button 1 and a detached load whose Light On has no group.",
    standardCommands: [lightOn, lightOff, readLevel],
    groupTypes: [light]
  )

  /// Three buttons, each with its own on-level, and a key beep that's set with an extended
  /// message while the program lock is on.
  static let buttonsCommands = CommandSet(
    id: "exampleButtons",
    name: "Example buttons",
    summary: "Per-button on-levels and a guarded key beep.",
    operatingFlags: [
      OperatingFlag(
        name: "keyBeep",
        summary: "Beeps on every button press.",
        query: .operatingFlags,
        bit: 0x02,
        on: 0x0A,
        off: 0x0B,
        extendedWhen: "programLock",
        label: "Key beep"
      ),
      OperatingFlag(name: "programLock", summary: "Locks the buttons' programming.", query: .operatingFlags, bit: 0x01, label: "Program lock")
    ],
    extendedSettings: ExtendedSettings(
      isPerButton: true,
      values: [
        SettingValue(name: "onLevel", summary: "The level a press turns on to.", position: 8, label: "On-level", unit: .percent, scale: 0.392157)
      ],
      writes: [
        SettingWrite(name: "onLevel", summary: "Sets a button's on-level.", selector: 0x06, isPerButton: true, bytes: [SettingWrite.Byte(position: 3, value: "onLevel")])
      ]
    ),
    standardCommands: [lightOn, lightOff, readLevel],
    groupTypes: [light]
  )

  /// The flags that are never written, or only turned off, each with the Set Operating Flags
  /// commands a catalog could give them. The programming lock is bit `0x02`, which
  /// ``SettingsModem`` sets with `0x0A` and clears with `0x0B`. An extended settings value,
  /// `operatingFlags`, holds the same byte, at D7, which the extended Set with selector `0x05`
  /// writes.
  static let guardedCommands = CommandSet(
    id: "exampleGuarded",
    name: "Example guarded",
    summary: "Flags that cut a device off from the modem, and a programming lock.",
    operatingFlags: [
      OperatingFlag(name: "programmingLock", summary: "Locks the device's programming.", query: .operatingFlags, bit: 0x02, on: 0x0A, off: 0x0B, label: "Programming lock"),
      OperatingFlag(name: "radioOff", summary: "Turns the radio off.", query: .operatingFlags, bit: 0x10, on: 0x0C, off: 0x0D, label: "Radio off"),
      OperatingFlag(name: "powerLineOff", summary: "Turns the powerline off.", query: .operatingFlags, bit: 0x20, on: 0x0E, off: 0x0F, label: "Powerline off"),
      OperatingFlag(name: "checksumRequired", summary: "Requires a checksum.", query: .operatingFlags, bit: 0x40, on: 0x10, off: 0x11, label: "Checksum required")
    ],
    extendedSettings: ExtendedSettings(
      isPerButton: false,
      values: [
        SettingValue(name: "operatingFlags", summary: "The operating flags, as Get Operating Flags reads them.", position: 7, label: "Operating flags")
      ],
      writes: [
        SettingWrite(name: "operatingFlags", summary: "Sets the operating flags.", selector: 0x05, isPerButton: false, bytes: [SettingWrite.Byte(position: 3, value: "operatingFlags")])
      ]
    ),
    standardCommands: [lightOn, lightOff, readLevel],
    groupTypes: [light]
  )

  // MARK: - Profiles

  static func profile(model: String, name: String, identity: ReportedIdentity, commands: CommandSet, groups: [DeviceProfile.Group]) -> DeviceProfile {

    DeviceProfile(
      model: ProductModel(rawValue: model),
      name: name,
      identities: [DeviceIdentity(category: identity.category, subcategory: identity.subcategory)],
      commandSets: [CommandSetEntry(commandSet: commands.id, category: identity.category, subcategory: identity.subcategory)],
      groups: groups
    )

  }

  static let catalog = DeviceCatalog(
    profiles: [
      profile(model: "9101", name: "Example Dimmer", identity: dimmerIdentity, commands: dimmerCommands, groups: [
        DeviceProfile.Group(number: 1, name: "Load", role: .both, type: "light")
      ]),
      profile(model: "9102", name: "Example Relay", identity: relayIdentity, commands: relayCommands, groups: [
        DeviceProfile.Group(number: 1, name: "Load", role: .both, type: "load")
      ]),
      profile(model: "9103", name: "Example Fan", identity: fanIdentity, commands: fanCommands, groups: [
        DeviceProfile.Group(number: 1, name: "Light", role: .both, type: "light"),
        DeviceProfile.Group(number: 2, name: "Fan", role: .both, type: "fan")
      ]),
      profile(model: "9104", name: "Example Outlet", identity: outletIdentity, commands: outletCommands, groups: [
        DeviceProfile.Group(number: 1, name: "Top outlet", role: .both, type: "top"),
        DeviceProfile.Group(number: 2, name: "Bottom outlet", role: .both, type: "bottom")
      ]),
      profile(model: "9105", name: "Example Keypad", identity: keypadIdentity, commands: keypadCommands, groups: [
        DeviceProfile.Group(number: 1, name: "Button A", role: .both, type: "light"),
        DeviceProfile.Group(number: 2, name: "Detached load", role: .both, type: "light")
      ]),
      profile(model: "9106", name: "Example Buttons", identity: buttonsIdentity, commands: buttonsCommands, groups: [
        DeviceProfile.Group(number: 1, name: "Button 1", role: .both, type: "light"),
        DeviceProfile.Group(number: 2, name: "Button 2", role: .controller),
        DeviceProfile.Group(number: 3, name: "Button 3", role: .controller)
      ]),
      profile(model: "9107", name: "Example Guarded", identity: guardedIdentity, commands: guardedCommands, groups: [
        DeviceProfile.Group(number: 1, name: "Load", role: .both, type: "light")
      ])
    ],
    commandSets: [dimmerCommands, relayCommands, fanCommands, outletCommands, keypadCommands, buttonsCommands, guardedCommands]
  )

}
