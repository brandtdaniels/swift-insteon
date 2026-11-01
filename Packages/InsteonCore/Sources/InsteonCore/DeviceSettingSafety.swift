import InsteonDeviceCatalog
import InsteonProtocol

/// The settings and commands that are never written, so no device is cut off from the modem,
/// left locked, or made to stop understanding it.
///
/// The Insteon device catalog marks them: an operating flag's or flags parameter bit's
/// `FlagGuard`, a command's `CommandGuard`, and a value's `SettingValue.flagsQuery`. A list
/// here is a floor under the catalog, so a catalog without those marks is guarded too: the
/// catalog can add guards, but never removes one of these.
enum DeviceSettingSafety {

  /// How a write treats a bit.
  enum Rule: Hashable, Sendable {

    /// A write leaves the bit as the device reported it.
    case keep

    /// A write may clear the bit but never sets it.
    case neverSet

  }

  /// A bit a value's byte holds that a write must guard, with the label of its flag.
  struct GuardedBit: Hashable, Sendable {

    /// The bit's mask in the byte.
    let mask: UInt8

    /// What a settings page calls the bit's flag.
    let label: String

    /// How a write treats the bit.
    let rule: Rule

  }

  /// The settings always kept as the device reported them, whatever the catalog says: turning
  /// off the radio or the powerline, and requiring a checksum in every message, which a modem
  /// that doesn't send one can't undo.
  static let neverWritten: Set<SettingName> = ["radioOff", "powerLineOff", "powerlineOff", "checksumRequired"]

  /// The programming lock, which is only ever turned off, whatever the catalog says.
  static let programmingLock: SettingName = "programmingLock"

  /// Set Operating Flags' cmd1, which the catalog's never-sent commands share.
  static let setOperatingFlagsCommand1: UInt8 = 0x20

  /// How a write treats a flag or bit: kept for a floor flag, a `keep` guard, or a guard this
  /// package doesn't know; never set for the programming lock or a `neverSet` guard; and
  /// written freely otherwise. The stricter rule wins.
  ///
  /// - Parameters:
  ///   - name: The flag's or bit's name.
  ///   - writeGuard: The catalog's guard for it, if any.
  /// - Returns: The rule, or `nil` if the bit is written freely.
  static func rule(named name: SettingName, writeGuard: FlagGuard?) -> Rule? {

    if neverWritten.contains(name) || (writeGuard != nil && writeGuard != .neverSet) {

      return .keep

    }

    if name == programmingLock || writeGuard == .neverSet {

      return .neverSet

    }

    return nil

  }

  /// How a write treats an operating flag.
  static func rule(for flag: OperatingFlag) -> Rule? {

    rule(named: flag.name, writeGuard: flag.writeGuard)

  }

  /// Whether the catalog marks a command as one an app never sends: any guard does, since a
  /// guard this package doesn't know is treated as the strictest.
  static func isNeverSent(_ commandGuard: CommandGuard?) -> Bool {

    commandGuard != nil

  }

  /// Commands never sent, whatever the catalog says, by their names in a command set: those
  /// that turn the programming lock on, the radio or the powerline off, or checksums on.
  static let neverSentNames: Set<SettingName> = [
    "programmingLockOn",
    "radioOff",
    "powerLineOff",
    "powerlineOff",
    "checksumOn",
    "checksumRequiredOn"
  ]

  /// Whether a standard command may be sent: it has no guard, isn't named as a command that's
  /// never sent, isn't Poke, whatever its cmd2, and, with a fixed cmd2, doesn't have the bytes
  /// of one.
  static func isSendable(_ command: DeviceStandardCommand, in commands: CommandSet?) -> Bool {

    guard !isNeverSent(command.sendGuard), !neverSentNames.contains(command.name), command.command1 != ProtectedCommand.pokeCommand1 else {

      return false

    }

    guard case let .fixed(command2) = command.command2 else {

      return true

    }

    return !isNeverSent(Command(command1: command.command1, command2: command2), in: commands)

  }

  /// Whether an extended command may be sent: it has no guard, isn't named as a command that's
  /// never sent, and doesn't have the bytes of one.
  static func isSendable(_ command: DeviceExtendedCommand, in commands: CommandSet?) -> Bool {

    !isNeverSent(command.sendGuard) && !neverSentNames.contains(command.name) && !isNeverSent(command.command, in: commands)

  }

  /// The bytes never sent to a device that uses a command set, by whatever route or name.
  ///
  /// They're derived from the flags a write guards, whether the catalog guards them or the
  /// floor names them: Set Operating Flags (cmd1 `0x20`) with a kept flag's on or off cmd2,
  /// or a never-set flag's on cmd2, and the fixed bytes of the standard commands such a flag
  /// names to change it. Added to them are the Set Operating Flags bytes of every flag,
  /// standard or extended command the catalog guards, or the floor names in
  /// ``neverSentNames``. So a command set with no guards at all, such as one with only a
  /// programming lock flag or a `programmingLockOn` command, still never sends those bytes
  /// under another name.
  ///
  /// Under them all is the byte floor, ``floorCommands(in:)``: the Set Operating Flags
  /// commands of ``ProtectedCommand``, sent only to a device whose command set names the cmd2
  /// for a flag that isn't guarded. Poke has no fixed cmd2, so it isn't among the bytes;
  /// ``isNeverSent(_:in:)`` refuses it by its cmd1.
  static func neverSentCommands(in commands: CommandSet?) -> Set<Command> {

    var never: Set<Command> = floorCommands(in: commands)

    guard let commands else {

      return never

    }

    func insertSetOperatingFlags(_ command2: UInt8?) {

      if let command2 {

        never.insert(Command(command1: setOperatingFlagsCommand1, command2: command2))

      }

    }

    func insertStandardCommand(named name: SettingName?) {

      guard let name, let command = commands.standardCommand(named: name), case let .fixed(command2) = command.command2 else {

        return

      }

      never.insert(Command(command1: command.command1, command2: command2))

    }

    for flag in commands.operatingFlags {

      switch rule(for: flag) {
      case .keep?:
        insertSetOperatingFlags(flag.on)
        insertSetOperatingFlags(flag.off)
        insertStandardCommand(named: flag.onCommand)
        insertStandardCommand(named: flag.offCommand)
      case .neverSet?:
        insertSetOperatingFlags(flag.on)
        insertStandardCommand(named: flag.onCommand)
      case nil:
        break
      }

    }

    for flagCommand in commands.flagCommands where isNeverSent(flagCommand.sendGuard) || neverSentNames.contains(flagCommand.name) {

      never.insert(flagCommand.command.command)

    }

    for standard in commands.standardCommands where standard.command1 == setOperatingFlagsCommand1 && (isNeverSent(standard.sendGuard) || neverSentNames.contains(standard.name)) {

      if case let .fixed(command2) = standard.command2 {

        never.insert(Command(command1: standard.command1, command2: command2))

      }

    }

    for extended in commands.extendedCommands where extended.command.command1 == setOperatingFlagsCommand1 && (isNeverSent(extended.sendGuard) || neverSentNames.contains(extended.name)) {

      never.insert(extended.command)

    }

    return never

  }

  /// The protected Set Operating Flags commands never sent to a device that uses a command
  /// set: all four with no command set, and otherwise each whose cmd2 the command set doesn't
  /// name for a flag it doesn't guard.
  ///
  /// The catalog's meaning wins where it gives one: an i3 Keypad's lock buttons flag is turned
  /// on with cmd2 `0x19`, which turns checksums on elsewhere, so it's sent to an i3 Keypad. A
  /// cmd2 the command set names for a guarded flag, such as radio off or the programming
  /// lock's on, or names for nothing, stays refused, and the catalog's guards still add their
  /// own bytes in ``neverSentCommands(in:)``.
  static func floorCommands(in commands: CommandSet?) -> Set<Command> {

    guard let commands else {

      return ProtectedCommand.setOperatingFlagsCommands

    }

    let named: Set<UInt8> = unguardedSetOperatingFlags(in: commands)

    return ProtectedCommand.setOperatingFlagsCommands.filter { (command: Command) -> Bool in !named.contains(command.command2) }

  }

  /// The Set Operating Flags cmd2s a command set names for a flag it doesn't guard: an
  /// operating flag's on or off, a flag command, and a standard or extended command with Set
  /// Operating Flags' cmd1 and a fixed cmd2, each with no guard and a name that neither the
  /// floor holds nor ``namesGuardedMeaning(_:)`` matches.
  static func unguardedSetOperatingFlags(in commands: CommandSet) -> Set<UInt8> {

    var named: Set<UInt8> = []

    for flag in commands.operatingFlags where rule(for: flag) == nil && !namesGuardedMeaning(flag.name) {

      if let on = flag.on {

        named.insert(on)

      }

      if let off = flag.off {

        named.insert(off)

      }

    }

    for flagCommand in commands.flagCommands where isUnguardedCommand(flagCommand.name, sendGuard: flagCommand.sendGuard) {

      let command: Command = flagCommand.command.command

      if command.command1 == setOperatingFlagsCommand1 {

        named.insert(command.command2)

      }

    }

    for standard in commands.standardCommands where standard.command1 == setOperatingFlagsCommand1 && isUnguardedCommand(standard.name, sendGuard: standard.sendGuard) {

      if case let .fixed(command2) = standard.command2 {

        named.insert(command2)

      }

    }

    for extended in commands.extendedCommands where extended.command.command1 == setOperatingFlagsCommand1 && isUnguardedCommand(extended.name, sendGuard: extended.sendGuard) {

      named.insert(extended.command.command2)

    }

    return named

  }

  /// Whether a command is one the command set doesn't guard: it has no guard, and its name is
  /// neither one the floor never sends nor one ``namesGuardedMeaning(_:)`` matches.
  private static func isUnguardedCommand(_ name: SettingName, sendGuard: CommandGuard?) -> Bool {

    !isNeverSent(sendGuard) && !neverSentNames.contains(name) && !namesGuardedMeaning(name)

  }

  /// The parts of a name that mean a guarded flag, in lowercase: the radio, the powerline,
  /// checksums and the programming lock.
  static let guardedMeanings: [String] = ["radiooff", "powerlineoff", "checksum", "programminglock"]

  /// Whether a name, in any case, means a guarded flag, such as `checksumRequired2` or
  /// `PowerLineOff`. A flag or command so named never unlocks a protected cmd2, even with no
  /// guard, so a catalog entry that gets its guard wrong stays refused.
  static func namesGuardedMeaning(_ name: SettingName) -> Bool {

    let lowercased: String = name.rawValue.lowercased()

    return guardedMeanings.contains { (meaning: String) -> Bool in lowercased.contains(meaning) }

  }

  /// Whether a command's bytes are ones never sent to a device that uses a command set, as
  /// ``neverSentCommands(in:)`` gives them, or Poke. Every message a ``Device`` sends is
  /// checked.
  static func isNeverSent(_ command: Command, in commands: CommandSet?) -> Bool {

    ProtectedCommand(command) == .poke || neverSentCommands(in: commands).contains(command)

  }

  /// Whether an item is never written: a flag that's kept, or one named in the floor, or a
  /// value whose only write is a command the command set never sends.
  static func isNeverWritten(_ item: SettingItem, in commands: CommandSet) -> Bool {

    if neverWritten.contains(item.name) {

      return true

    }

    switch item.source {
    case let .flag(flag):
      switch rule(for: flag) {
      case .keep?:
        return true
      case .neverSet?:
        // Only ever turned off, so it's written only if turning it off is sent.
        return commands.change(for: flag, setting: false).map { (change: FlagChange) -> Bool in sendsNeverSentCommand(change, in: commands) } ?? false
      case nil:
        // Written either way, so it's never written only when both ways are refused by their
        // bytes; a flag one way is refused, such as one whose on is a never-sent command's
        // bytes, can still be turned the other way.
        return [true, false].allSatisfy { (state: Bool) -> Bool in

          commands.change(for: flag, setting: state).map { (change: FlagChange) -> Bool in sendsNeverSentCommand(change, in: commands) } ?? false

        }
      }
    case .reading:
      return false
    case let .value(value):
      guard case let .extendedCommand(command) = commands.change(for: value) else {

        return false

      }

      return !isSendable(command, in: commands)
    }

  }

  /// Whether giving a flag a state would set a bit that's never set.
  static func setsNeverSetFlag(_ item: SettingItem, state: Bool) -> Bool {

    guard state, case let .flag(flag) = item.source else {

      return false

    }

    return rule(for: flag) == .neverSet

  }

  /// Whether a change to a flag sends a command the command set never sends.
  static func sendsNeverSentCommand(_ change: FlagChange, in commands: CommandSet) -> Bool {

    switch change {
    case let .setOperatingFlags(command2):
      return isNeverSent(Command(command1: setOperatingFlagsCommand1, command2: command2), in: commands)
    case let .standardCommand(command):
      return !isSendable(command, in: commands)
    }

  }

  /// Extended settings values whose byte is a Get Operating Flags reply's cmd2, by command set
  /// and value, with the request whose reply it is, for a catalog that doesn't give their
  /// `SettingValue.flagsQuery`. A value named `operatingFlags` in any command set is taken to
  /// be Get Operating Flags `0x00`'s byte too.
  static let operatingFlagsValues: [CommandSetID: [SettingName: OperatingFlagsRequest]] = [
    "openCloseSensor": ["configuration": .operatingFlags],
    "hiddenDoorSensor": ["operatingFlags": .operatingFlags]
  ]

  /// The value name that holds Get Operating Flags `0x00`'s byte in any command set.
  static let operatingFlagsValue: SettingName = "operatingFlags"

  /// The Get Operating Flags queries whose reply a value's byte may be: the catalog's
  /// `SettingValue.flagsQuery` and the floor's, both, so a catalog that names another query
  /// for a byte the floor lists never unguards it.
  static func flagsQueries(of value: SettingValue, in commands: CommandSet) -> Set<OperatingFlagsRequest> {

    var queries: Set<OperatingFlagsRequest> = []

    if let query = value.flagsQuery {

      queries.insert(query)

    }

    if let listed = operatingFlagsValues[commands.id]?[value.name] {

      queries.insert(listed)

    }

    if value.name == operatingFlagsValue {

      queries.insert(.operatingFlags)

    }

    return queries

  }

  /// The bits of a value's byte a write must guard: the guarded operating flags the byte
  /// holds, and the guarded bits of the flags parameter of the extended command that writes
  /// it.
  ///
  /// Writing such a byte writes every bit in it, so it never sets a bit that's never set, and
  /// never changes one that's kept.
  ///
  /// - Parameters:
  ///   - value: The value.
  ///   - commands: Its command set.
  /// - Returns: The bits, or none if the value's byte holds none.
  static func guardedBits(in value: SettingValue, of commands: CommandSet) -> [GuardedBit] {

    var bits: [GuardedBit] = []

    let queries: Set<OperatingFlagsRequest> = flagsQueries(of: value, in: commands)

    if !queries.isEmpty {

      for flag in commands.operatingFlags where queries.contains(flag.query) {

        if let flagRule = rule(for: flag) {

          bits.append(GuardedBit(mask: flag.bit, label: SettingItem(flag: flag).label, rule: flagRule))

        }

      }

    }

    if case let .extendedCommand(command) = commands.change(for: value), let parameter = parameter(of: command, for: value), case let .flags(fieldBits) = parameter.kind {

      for bit in fieldBits {

        if let bitRule = rule(named: bit.name, writeGuard: bit.writeGuard) {

          let label: String = commands.operatingFlag(named: bit.name).map { (flag: OperatingFlag) -> String in SettingItem(flag: flag).label } ?? bit.name.rawValue

          bits.append(GuardedBit(mask: bit.mask, label: label, rule: bitRule))

        }

      }

    }

    return bits

  }

  /// The label of a guarded flag that an extended message sent as it's given writes, or `nil`
  /// if it writes none the command set knows of.
  ///
  /// Such a message comes from a raw passthrough or the catalog's keep-awake message, so its
  /// bytes aren't checked against what the device reported first, as
  /// `Device.writeSetting(_:to:button:)` checks them: any guarded bit in a byte it writes
  /// refuses it, whatever the bit's value. A byte is written by an extended Set whose D2 is the
  /// selector of one of the command set's extended settings writes, and by an extended command
  /// of the command set with the same cmd1 and cmd2 and fixed bytes: through the values it
  /// writes, and through a flags parameter.
  ///
  /// - Parameters:
  ///   - command: The message's cmd1 and cmd2.
  ///   - userData: The message's user data.
  ///   - commands: The device's command set.
  /// - Returns: The label of a guarded flag, or `nil`.
  static func guardedFlagWritten(by command: Command, userData: UserData, in commands: CommandSet) -> String? {

    let settings: ExtendedSettings? = commands.extendedSettings

    // An extended Set (cmd1 0x2E, cmd2 0x00) with a selector in D2; 0x00 is the Get.
    if command == Command(command1: 0x2E, command2: 0x00), userData[2] != 0x00, let settings {

      for write in settings.writes where write.selector == userData[2] {

        for byte in write.bytes {

          if let value = settings.value(named: byte.value), let bit = guardedBits(in: value, of: commands).first {

            return bit.label

          }

        }

      }

    }

    for extended in commands.extendedCommands where extended.command == command {

      let matches: Bool = extended.fixedBytes.allSatisfy { (byte: FixedUserDataByte) -> Bool in userData[byte.position] == byte.value }

      guard matches else {

        continue

      }

      for parameter in extended.parameters {

        guard case let .flags(bits) = parameter.kind else {

          continue

        }

        for bit in bits where rule(named: bit.name, writeGuard: bit.writeGuard) != nil {

          return commands.operatingFlag(named: bit.name).map { (flag: OperatingFlag) -> String in SettingItem(flag: flag).label } ?? bit.name.rawValue

        }

      }

      for value in settings?.values ?? [] where value.write == extended.name {

        if let bit = guardedBits(in: value, of: commands).first {

          return bit.label

        }

      }

    }

    return nil

  }

  /// Whether a message is an extended Set: cmd1 `0x2E` and cmd2 `0x00` with a selector other
  /// than `0x00` in D2, which writes whatever bytes the device's selector names.
  static func isExtendedSet(_ command: Command, userData: UserData) -> Bool {

    command == Command(command1: 0x2E, command2: 0x00) && userData[2] != 0x00

  }

  /// The parameter of an extended command a value is written into: the value's own, or else
  /// the command's only one, as `ValueChange.message(to:button:setting:to:current:)` chooses it.
  private static func parameter(of command: DeviceExtendedCommand, for value: SettingValue) -> MessageField? {

    let named: MessageField? = command.parameters.first { (field: MessageField) -> Bool in field.name == value.name }

    return named ?? (command.parameters.count == 1 ? command.parameters.first : nil)

  }

}
