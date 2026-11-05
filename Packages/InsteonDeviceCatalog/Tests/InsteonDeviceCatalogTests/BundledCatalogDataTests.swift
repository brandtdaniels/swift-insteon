import Testing
import InsteonDeviceCatalog
import InsteonProtocol

/// The bundled catalog's data that the libraries act on: the guards that keep a device
/// reachable and unlocked, the messages that keep a sleeping device awake, the values that hold
/// an operating flags byte, and the groups whose state, outputs and arm modes come from their
/// group type. The libraries' own tests use invented catalogs; these check that the real one
/// says what those tests take a catalog to say.
struct BundledCatalogDataTests {

  /// The bundled catalog.
  static func catalog() throws -> DeviceCatalog {

    try DeviceCatalog.bundled()

  }

  /// A command set of the bundled catalog.
  static func commands(_ id: CommandSetID) throws -> CommandSet {

    try #require(try catalog().commandSet(id: id))

  }

  /// The Set Operating Flags command with a cmd2.
  static func setOperatingFlags(_ command2: UInt8) -> Command {

    Command(command1: 0x20, command2: command2)

  }

  /// A flag command of a command set, by name.
  static func flagCommand(_ name: SettingName, in commands: CommandSet) throws -> OperatingFlagCommand {

    try #require(commands.flagCommands.first { (command: OperatingFlagCommand) -> Bool in command.name == name }, "\(commands.id) \(name)")

  }

  // MARK: - Guards

  /// The parts of a name, in lowercase, that mean a flag that cuts a device off from the
  /// modem or locks it: turning off its radio or powerline, requiring a checksum, and locking
  /// its programming.
  static let lockingOrIsolatingMeanings: [String] = ["radiooff", "powerlineoff", "checksum", "programminglock"]

  /// The Set Operating Flags cmd2s that cut most devices off from the modem or lock them.
  static let protectedCommand2s: Set<UInt8> = [0x00, 0x0C, 0x0E, 0x19]

  /// Whether a name means a flag that cuts a device off from the modem or locks it.
  static func meansLockingOrIsolating(_ name: SettingName) -> Bool {

    let lowercased: String = name.rawValue.lowercased()

    return lockingOrIsolatingMeanings.contains { (meaning: String) -> Bool in lowercased.contains(meaning) }

  }

  @Test func guardsEveryFlagThatCutsADeviceOffOrLocksIt() throws {

    var checked: Int = 0

    for commands in try Self.catalog().commandSets {

      for flag in commands.operatingFlags {

        switch flag.name.rawValue {
        case "radioOff", "powerLineOff", "powerlineOff", "checksumRequired":
          checked += 1
          #expect(flag.writeGuard == .keep, "\(commands.id) \(flag.name)")
        case "programmingLock":
          checked += 1
          #expect(flag.writeGuard == .neverSet || flag.writeGuard == .keep, "\(commands.id) \(flag.name)")
        default:
          // Any other flag so named that's turned on with a protected cmd2 is guarded too.
          if Self.meansLockingOrIsolating(flag.name), let on = flag.on, Self.protectedCommand2s.contains(on) {

            #expect(flag.writeGuard != nil, "\(commands.id) \(flag.name)")

          }
        }

      }

    }

    #expect(checked > 0)

  }

  @Test func neverSendsACommandThatCutsADeviceOffOrLocksIt() throws {

    var checked: Int = 0

    for commands in try Self.catalog().commandSets {

      var named: [(SettingName, Command?, CommandGuard?)] = commands.flagCommands.map { (command: OperatingFlagCommand) -> (SettingName, Command?, CommandGuard?) in

        (command.name, command.command.command, command.sendGuard)

      }

      named += commands.standardCommands.map { (command: DeviceStandardCommand) -> (SettingName, Command?, CommandGuard?) in

        guard case let .fixed(command2) = command.command2 else {

          return (command.name, nil, command.sendGuard)

        }

        return (command.name, Command(command1: command.command1, command2: command2), command.sendGuard)

      }

      named += commands.extendedCommands.map { (command: DeviceExtendedCommand) -> (SettingName, Command?, CommandGuard?) in (command.name, command.command, command.sendGuard) }

      for (name, command, sendGuard) in named {

        let isNamedProtected: Bool = ["programmingLockOn", "radioOff", "powerLineOff", "powerlineOff", "checksumOn", "checksumRequiredOn"].contains(name.rawValue)
        let isProtectedBytes: Bool = command.map { (command: Command) -> Bool in command.command1 == 0x20 && Self.protectedCommand2s.contains(command.command2) } ?? false

        if isNamedProtected || (Self.meansLockingOrIsolating(name) && isProtectedBytes) {

          checked += 1
          #expect(sendGuard == .never, "\(commands.id) \(name)")

        }

      }

    }

    #expect(checked > 0)

  }

  @Test func marksEveryValueNamedForTheOperatingFlagsByte() throws {

    for commands in try Self.catalog().commandSets {

      for value in commands.extendedSettings?.values ?? [] where value.name == "operatingFlags" {

        #expect(value.flagsQuery == .operatingFlags, "\(commands.id) \(value.name)")

      }

    }

  }

  @Test func guardsTheFlagsThatShareAProtectedCmd2WithAnUnguardedOne() throws {

    let i3Keypad: CommandSet = try Self.commands("i3Keypad")
    let keypadLinc: CommandSet = try Self.commands("keypadLinc")

    // The i3 Keypad turns lockButtons on with 0x19 and keeps radioOff.
    let lockButtons: OperatingFlag = try #require(i3Keypad.operatingFlag(named: "lockButtons"))

    #expect(lockButtons.on == 0x19)
    #expect(lockButtons.writeGuard == nil)
    #expect(i3Keypad.operatingFlag(named: "radioOff")?.writeGuard == .keep)
    #expect(i3Keypad.operatingFlag(named: "radioOff")?.on == 0x0C)
    #expect(i3Keypad.operatingFlag(named: "programmingLock")?.writeGuard == .neverSet)
    #expect(i3Keypad.operatingFlag(named: "programmingLock")?.on == 0x00)

    // A KeypadLinc names 0x19 for checksumRequired, which is kept.
    let checksum: OperatingFlag = try #require(keypadLinc.operatingFlag(named: "checksumRequired"))

    #expect(checksum.on == 0x19)
    #expect(checksum.writeGuard == .keep)
    #expect(keypadLinc.operatingFlag(named: "radioOff").map { (flag: OperatingFlag) -> [UInt8?] in [flag.on, flag.off] } == [0x0C, 0x0D])
    #expect(keypadLinc.operatingFlag(named: "radioOff")?.writeGuard == .keep)
    #expect(keypadLinc.operatingFlag(named: "programmingLock")?.writeGuard == .neverSet)

  }

  @Test func guardsTheExtendedAndFlagCommandsThatLockADevice() throws {

    let tempLinc: CommandSet = try Self.commands("tempLinc")
    let scheduleTimer: CommandSet = try Self.commands("keypadLincScheduleTimer")

    // The thermostat's heatCoolLedOn is Set Operating Flags 0x0C, an extended command with no
    // guard; its programmingLockOn, 0x00, is never sent.
    #expect(tempLinc.extendedCommand(named: "heatCoolLedOn")?.command == Self.setOperatingFlags(0x0C))
    #expect(tempLinc.extendedCommand(named: "heatCoolLedOn")?.sendGuard == nil)
    #expect(tempLinc.extendedCommand(named: "programmingLockOn")?.command == Self.setOperatingFlags(0x00))
    #expect(tempLinc.extendedCommand(named: "programmingLockOn")?.sendGuard == .never)
    #expect(tempLinc.extendedCommand(named: "programmingLockOff")?.sendGuard == nil)

    let lockOn: OperatingFlagCommand = try Self.flagCommand("programmingLockOn", in: scheduleTimer)

    #expect(lockOn.command.command == Self.setOperatingFlags(0x00))
    #expect(lockOn.sendGuard == .never)

  }

  @Test func guardsTheOutdoorPlugsFlagCommandsThatCutItOff() throws {

    for id: CommandSetID in ["outdoorApplianceLinc", "outdoorApplianceLincFirmware42"] {

      let outdoor: CommandSet = try Self.commands(id)

      for (name, command2) in [("radioOff", UInt8(0x0C)), ("powerLineOff", 0x0E), ("checksumOn", 0x19)] as [(SettingName, UInt8)] {

        let command: OperatingFlagCommand = try Self.flagCommand(name, in: outdoor)

        #expect(command.command.command == Self.setOperatingFlags(command2), "\(id) \(name)")
        #expect(command.sendGuard == .never, "\(id) \(name)")

      }

      #expect(outdoor.flagCommands.first { (command: OperatingFlagCommand) -> Bool in command.command.command == Self.setOperatingFlags(0x0D) }?.sendGuard == nil, "\(id)")

    }

    // Firmware 0x42 has a programming lock flag, never set.
    let description: DeviceDescription = try Self.catalog().describe(category: 0x02, subcategory: 0x38, firmwareVersion: 0x42)

    #expect(description.commandSet?.id == "outdoorApplianceLincFirmware42")
    #expect(description.commandSet?.operatingFlag(named: "programmingLock")?.writeGuard == .neverSet)

  }

  @Test func guardsTheI3FlagsParameterBits() throws {

    for id: CommandSetID in ["i3Paddle", "i3Keypad", "i3Dial"] {

      let writeProperties: DeviceExtendedCommand = try #require(try Self.commands(id).extendedCommand(named: "writeProperties"), "\(id)")
      let flags00: MessageField = try #require(writeProperties.parameters.first { (field: MessageField) -> Bool in field.name == "flags00" }, "\(id)")

      guard case let .flags(bits) = flags00.kind else {

        Issue.record("Expected \(id)'s flags00 to be flags, got \(String(describing: flags00.kind)).")

        continue

      }

      let guards: [UInt8: FlagGuard?] = Dictionary(uniqueKeysWithValues: bits.map { (bit: FieldBit) -> (UInt8, FlagGuard?) in (bit.mask, bit.writeGuard) })

      #expect(bits.first { (bit: FieldBit) -> Bool in bit.mask == 0x01 }?.name == "programmingLock", "\(id)")
      #expect(guards[0x01] == .neverSet, "\(id)")
      #expect(bits.first { (bit: FieldBit) -> Bool in bit.mask == 0x40 }?.name == "radioOff", "\(id)")
      #expect(guards[0x40] == .keep, "\(id)")

    }

  }

  // MARK: - Flags bytes

  @Test func marksTheValuesThatHoldTheOperatingFlagsByte() throws {

    let openClose: CommandSet = try Self.commands("openCloseSensor")
    let hiddenDoor: CommandSet = try Self.commands("hiddenDoorSensor")

    // The open/close sensor's configuration byte is Get Operating Flags 0x00's, whose bit 0x80
    // is the programming lock.
    #expect(openClose.extendedSettings?.value(named: "configuration")?.flagsQuery == .operatingFlags)
    #expect(openClose.operatingFlag(named: "programmingLock").map { (flag: OperatingFlag) -> UInt8 in flag.bit } == 0x80)
    #expect(openClose.operatingFlag(named: "programmingLock")?.query == .operatingFlags)
    #expect(openClose.operatingFlag(named: "programmingLock")?.writeGuard == .neverSet)
    #expect(hiddenDoor.extendedSettings?.value(named: "operatingFlags")?.flagsQuery == .operatingFlags)

  }

  // MARK: - Keeping a device awake

  @Test func keepsTheOpenCloseSensorAwakeWithItsExtendedSet() throws {

    let description: DeviceDescription = try Self.catalog().describe(category: 0x10, subcategory: 0x02, firmwareVersion: 0x41)
    let keepAwake: DeviceLifecycle.HubLinking.KeepAwake = try #require(description.hubLinking?.keepAwake)
    let stayAwake: DeviceExtendedCommand = try #require(description.commandSet?.extendedCommand(named: "stayAwake"))

    #expect(keepAwake.timing == .afterLinked)
    #expect(keepAwake.send == .command("stayAwake"))
    #expect(keepAwake.release == nil)
    #expect(stayAwake.command == Command(command1: 0x2E, command2: 0x00))
    #expect(stayAwake.fixedBytes == [FixedUserDataByte(position: 1, value: 0x01), FixedUserDataByte(position: 2, value: 0x04)])
    #expect(stayAwake.parameters.map(\.location) == [.userData([3])])
    #expect(stayAwake.parameters.first?.kind == .number(unit: .seconds))

  }

  @Test func keepsTheRemoteLinc2AwakeWithItsStayAwakeFlag() throws {

    let description: DeviceDescription = try Self.catalog().describe(category: 0x00, subcategory: 0x10, firmwareVersion: 0x37)
    let keepAwake: DeviceLifecycle.HubLinking.KeepAwake = try #require(description.hubLinking?.keepAwake)
    let flag: OperatingFlag = try #require(description.commandSet?.operatingFlag(named: "stayAwake"))

    #expect(keepAwake.timing == .afterLinked)
    #expect(keepAwake.send == .flag(DeviceProfile.Group.Condition(flag: "stayAwake", isSet: true)))
    #expect(keepAwake.release == .flag(DeviceProfile.Group.Condition(flag: "stayAwake", isSet: false)))
    #expect([flag.on, flag.off] == [0x06, 0x07])

  }

  @Test func keepsTheWirelessZoneThermostatAwakeWithSetOperatingFlagsBeforeLinking() throws {

    let description: DeviceDescription = try Self.catalog().describe(category: 0x05, subcategory: 0x0A, firmwareVersion: 0x41)
    let keepAwake: DeviceLifecycle.HubLinking.KeepAwake = try #require(description.hubLinking?.keepAwake)

    #expect(keepAwake.timing == .beforeLinking)
    #expect(keepAwake.send == .bytes(DeviceLifecycle.HubLinking.RawMessage(command: Self.setOperatingFlags(0x06), isExtended: true, integrity: .checksum)))
    #expect(keepAwake.release == .bytes(DeviceLifecycle.HubLinking.RawMessage(command: Self.setOperatingFlags(0x07), isExtended: true, integrity: .checksum)))
    #expect(description.hubLinkingLegs.count == 4)

  }

  @Test func letsTheHiddenDoorSensorSleepAgainWithAnUnguardedFlagCommand() throws {

    let description: DeviceDescription = try Self.catalog().describe(category: 0x10, subcategory: 0x11, firmwareVersion: 0x41)
    let keepAwake: DeviceLifecycle.HubLinking.KeepAwake = try #require(description.hubLinking?.keepAwake)
    let commands: CommandSet = try #require(description.commandSet)
    let on: OperatingFlagCommand = try Self.flagCommand("stayAwakeOn", in: commands)
    let off: OperatingFlagCommand = try Self.flagCommand("stayAwakeOff", in: commands)

    #expect(keepAwake.send == .command("stayAwakeOn"))
    #expect(keepAwake.release == .command("stayAwakeOff"))
    #expect(on.command.command == Self.setOperatingFlags(0x18))
    #expect(off.command.command == Self.setOperatingFlags(0x19))
    #expect(on.sendGuard == nil)
    #expect(off.sendGuard == nil)

  }

  // MARK: - Groups

  @Test func readsEachEZFloraZoneFromTheSharedValveStatus() throws {

    let description: DeviceDescription = try Self.catalog().describe(category: 0x04, subcategory: 0x00, firmwareVersion: nil)

    for zone in 1...8 {

      let type: GroupType = try #require(description.groupType(forGroup: AllLinkGroupNumber(rawValue: UInt8(zone))), "zone \(zone)")

      #expect(type.state?.command == "readValveStatus", "zone \(zone)")
      #expect(type.state?.onWhen?.mask == 0x87, "zone \(zone)")
      #expect(type.state?.onWhen?.value == 0x80 | UInt8(zone - 1), "zone \(zone)")

    }

  }

  @Test func switchesTheBallastDimmersRelaysInRelayMode() throws {

    let description: DeviceDescription = try Self.catalog().describe(category: 0x01, subcategory: 0x25, firmwareVersion: 0x41)
    let outputs: GroupType.Outputs = try #require(description.groupType(forGroup: 1)?.outputs)
    let relayMode: OperatingFlag = try #require(description.commandSet?.operatingFlag(named: "relayMode"))

    #expect(outputs.activeWhen == DeviceProfile.Group.Condition(flag: "relayMode", isSet: true))
    #expect(outputs.bits.map(\.name) == ["relay1", "relay2"])
    #expect(outputs.bits.map(\.mask) == [0x01, 0x02])
    #expect(relayMode.query == OperatingFlagsRequest(rawValue: 0x05))
    #expect(relayMode.bit == 0x80)

  }

  @Test func givesTheSirensGroupsTheirArmModes() throws {

    let description: DeviceDescription = try Self.catalog().describe(category: 0x07, subcategory: 0x1E, firmwareVersion: 0x41)
    let modes: [[String]] = try (1...6).map { (group: Int) -> [String] in

      try #require(description.groupType(forGroup: AllLinkGroupNumber(rawValue: UInt8(group)))).armModes.map(\.rawValue)

    }

    #expect(modes == [["away"], ["away"], ["home"], ["home"], ["home", "away"], ["home", "away"]])

  }

}
