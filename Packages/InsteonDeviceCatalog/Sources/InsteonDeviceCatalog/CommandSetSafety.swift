import InsteonProtocol

/// The settings and commands that are never written, so no device is cut off from the modem,
/// left locked, or made to stop understanding it, as InsteonCore applies them at send time and
/// as ``DeviceCatalog/guardWeakenings(comparedTo:)`` compares two catalogs by them.
///
/// The catalog marks them: an operating flag's or flags parameter bit's ``FlagGuard``, a
/// command's ``CommandGuard``, and a value's ``SettingValue/flagsQuery``. Under them is a
/// floor of bytes, ``protectedSetOperatingFlags``: a protected Set Operating Flags cmd2 is
/// refused unless the device's command set names it through a flag or command it doesn't
/// guard, and Poke is always refused. So the floor holds for a device the catalog doesn't know
/// and for a cmd2 its command set doesn't name, but a command set that names a protected cmd2
/// through an unguarded entry unlocks it.
package enum CommandSetSafety {

  /// How a write treats a bit.
  package enum Rule: Hashable, Sendable {

    /// A write leaves the bit as the device reported it.
    case keep

    /// A write may clear the bit but never sets it.
    case neverSet

  }

  /// A bit a value's byte holds that a write must guard, with the label of its flag.
  package struct GuardedBit: Hashable, Sendable {

    /// The bit's mask in the byte.
    package let mask: UInt8

    /// What a settings page calls the bit's flag.
    package let label: String

    /// How a write treats the bit.
    package let rule: Rule

  }

  /// Set Operating Flags' cmd1, which the catalog's never-sent commands share.
  package static let setOperatingFlagsCommand1: UInt8 = 0x20

  /// Poke One Byte's cmd1, which writes any byte of a device's memory, so it's never sent,
  /// whatever its cmd2.
  package static let pokeCommand1: UInt8 = 0x29

  /// The floor of bytes under every guard: Set Operating Flags with the cmd2s that cut most
  /// devices off from the modem or lock them, `0x00`, `0x0C`, `0x0E` and `0x19`. InsteonCore's
  /// `ProtectedCommand` names the same four.
  package static let protectedSetOperatingFlags: Set<Command> = Set([UInt8(0x00), 0x0C, 0x0E, 0x19].map { (command2: UInt8) -> Command in Command(command1: setOperatingFlagsCommand1, command2: command2) })

  /// How a write treats a flag or bit with the catalog's guard: kept for a `keep` guard or a
  /// guard this package doesn't know, never set for a `neverSet` guard, and written freely with
  /// no guard.
  ///
  /// - Parameter writeGuard: The catalog's guard for the flag or bit, if any.
  /// - Returns: The rule, or `nil` if the bit is written freely.
  package static func rule(for writeGuard: FlagGuard?) -> Rule? {

    switch writeGuard {
    case nil:
      nil
    case .neverSet?:
      .neverSet
    case _?:
      .keep
    }

  }

  /// How a write treats an operating flag.
  package static func rule(for flag: OperatingFlag) -> Rule? {

    rule(for: flag.writeGuard)

  }

  /// Whether the catalog marks a command as one an app never sends: any guard does, since a
  /// guard this package doesn't know is treated as the strictest.
  package static func isNeverSent(_ commandGuard: CommandGuard?) -> Bool {

    commandGuard != nil

  }

  /// Whether a standard command may be sent: it has no guard, isn't Poke, whatever its cmd2,
  /// and, with a fixed cmd2, doesn't have the bytes of a command that's never sent.
  package static func isSendable(_ command: DeviceStandardCommand, in commands: CommandSet?) -> Bool {

    guard !isNeverSent(command.sendGuard), command.command1 != pokeCommand1 else {

      return false

    }

    guard case let .fixed(command2) = command.command2 else {

      return true

    }

    return !isNeverSent(Command(command1: command.command1, command2: command2), in: commands)

  }

  /// Whether an extended command may be sent: it has no guard, and doesn't have the bytes of a
  /// command that's never sent.
  package static func isSendable(_ command: DeviceExtendedCommand, in commands: CommandSet?) -> Bool {

    !isNeverSent(command.sendGuard) && !isNeverSent(command.command, in: commands)

  }

  /// The bytes never sent to a device that uses a command set, by whatever route or name.
  ///
  /// They're derived from the flags the catalog guards: Set Operating Flags (cmd1 `0x20`) with
  /// a kept flag's on or off cmd2, or a never-set flag's on cmd2, and the fixed bytes of the
  /// standard commands such a flag names to change it. Added to them are the Set Operating
  /// Flags bytes of every flag command, standard or extended command the catalog guards, so
  /// those bytes are never sent under another name either.
  ///
  /// Under them all is the byte floor, ``floorCommands(in:)``: the Set Operating Flags
  /// commands of ``protectedSetOperatingFlags``, sent only to a device whose command set names the cmd2
  /// for a flag that isn't guarded. Poke has no fixed cmd2, so it isn't among the bytes;
  /// ``isNeverSent(_:in:)`` refuses it by its cmd1.
  package static func neverSentCommands(in commands: CommandSet?) -> Set<Command> {

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

    for flagCommand in commands.flagCommands where isNeverSent(flagCommand.sendGuard) {

      never.insert(flagCommand.command.command)

    }

    for standard in commands.standardCommands where standard.command1 == setOperatingFlagsCommand1 && isNeverSent(standard.sendGuard) {

      if case let .fixed(command2) = standard.command2 {

        never.insert(Command(command1: standard.command1, command2: command2))

      }

    }

    for extended in commands.extendedCommands where extended.command.command1 == setOperatingFlagsCommand1 && isNeverSent(extended.sendGuard) {

      never.insert(extended.command)

    }

    return never

  }

  /// The protected Set Operating Flags commands never sent to a device that uses a command
  /// set: all four with no command set, and otherwise each whose cmd2 the command set doesn't
  /// name for a flag it doesn't guard.
  ///
  /// The catalog's meaning wins where it gives one: a keypad whose button lock flag is turned
  /// on with cmd2 `0x19`, which turns checksums on elsewhere, is sent `0x19`. A cmd2 the
  /// command set names for a guarded flag or command, or names for nothing, stays refused, and
  /// the catalog's guards still add their own bytes in ``neverSentCommands(in:)``.
  package static func floorCommands(in commands: CommandSet?) -> Set<Command> {

    guard let commands else {

      return protectedSetOperatingFlags

    }

    let named: Set<UInt8> = unguardedSetOperatingFlags(in: commands)

    return protectedSetOperatingFlags.filter { (command: Command) -> Bool in !named.contains(command.command2) }

  }

  /// The Set Operating Flags cmd2s a command set names for a flag it doesn't guard: an
  /// operating flag's on or off, a flag command, and a standard or extended command with Set
  /// Operating Flags' cmd1 and a fixed cmd2, each with no guard.
  package static func unguardedSetOperatingFlags(in commands: CommandSet) -> Set<UInt8> {

    var named: Set<UInt8> = []

    for flag in commands.operatingFlags where rule(for: flag) == nil {

      if let on = flag.on {

        named.insert(on)

      }

      if let off = flag.off {

        named.insert(off)

      }

    }

    for flagCommand in commands.flagCommands where !isNeverSent(flagCommand.sendGuard) {

      let command: Command = flagCommand.command.command

      if command.command1 == setOperatingFlagsCommand1 {

        named.insert(command.command2)

      }

    }

    for standard in commands.standardCommands where standard.command1 == setOperatingFlagsCommand1 && !isNeverSent(standard.sendGuard) {

      if case let .fixed(command2) = standard.command2 {

        named.insert(command2)

      }

    }

    for extended in commands.extendedCommands where extended.command.command1 == setOperatingFlagsCommand1 && !isNeverSent(extended.sendGuard) {

      named.insert(extended.command.command2)

    }

    return named

  }

  /// Whether a command's bytes are ones never sent to a device that uses a command set, as
  /// ``neverSentCommands(in:)`` gives them, or Poke. Every message a ``Device`` sends is
  /// checked.
  package static func isNeverSent(_ command: Command, in commands: CommandSet?) -> Bool {

    command.command1 == pokeCommand1 || neverSentCommands(in: commands).contains(command)

  }

  /// Whether an item is never written: a flag that's kept, or a value whose only write is a
  /// command the command set never sends.
  package static func isNeverWritten(_ item: SettingItem, in commands: CommandSet) -> Bool {

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
  package static func setsNeverSetFlag(_ item: SettingItem, state: Bool) -> Bool {

    guard state, case let .flag(flag) = item.source else {

      return false

    }

    return rule(for: flag) == .neverSet

  }

  /// Whether a change to a flag sends a command the command set never sends.
  package static func sendsNeverSentCommand(_ change: FlagChange, in commands: CommandSet) -> Bool {

    switch change {
    case let .setOperatingFlags(command2):
      return isNeverSent(Command(command1: setOperatingFlagsCommand1, command2: command2), in: commands)
    case let .standardCommand(command):
      return !isSendable(command, in: commands)
    }

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
  package static func guardedBits(in value: SettingValue, of commands: CommandSet) -> [GuardedBit] {

    var bits: [GuardedBit] = []

    for flag in commands.flagsHeld(by: value) {

      if let flagRule = rule(for: flag) {

        bits.append(GuardedBit(mask: flag.bit, label: SettingItem(flag: flag).label, rule: flagRule))

      }

    }

    if case let .extendedCommand(command) = commands.change(for: value), let parameter = parameter(of: command, for: value), case let .flags(fieldBits) = parameter.kind {

      for bit in fieldBits {

        if let bitRule = rule(for: bit.writeGuard) {

          let label: String = commands.operatingFlag(named: bit.name).map { (flag: OperatingFlag) -> String in SettingItem(flag: flag).label } ?? bit.name.rawValue

          bits.append(GuardedBit(mask: bit.mask, label: label, rule: bitRule))

        }

      }

    }

    return bits

  }

  /// Where a written byte goes: an extended Set's selector and the byte's D position, or an
  /// extended command's cmd1, cmd2 and fixed bytes and the byte's D position. Every message
  /// that writes a byte the command set describes writes it on one of these.
  package enum ByteRoute: Hashable, Sendable {

    case extendedSet(selector: UInt8, position: Int)

    case extendedCommand(Command, [FixedUserDataByte], position: Int)

  }

  /// The guarded bits of a byte on a route, with where an extended Get reports the byte's
  /// current value, or `nil` when nothing reports it.
  package struct RouteGuard: Hashable, Sendable {

    /// The D position of the extended Get reply that reports the byte, or `nil` if none does.
    package let readPosition: Int?

    /// The guarded bits.
    package let bits: [GuardedBit]

  }

  /// The guarded operating flag bits a value's byte holds, as its `SettingValue.flagsQuery`
  /// says.
  package static func flagsQueryBits(of value: SettingValue, in commands: CommandSet) -> [GuardedBit] {

    commands.flagsHeld(by: value).compactMap { (flag: OperatingFlag) -> GuardedBit? in

      rule(for: flag).map { (flagRule: Rule) -> GuardedBit in GuardedBit(mask: flag.bit, label: SettingItem(flag: flag).label, rule: flagRule) }

    }

  }

  /// The guarded bits of an extended command's flags parameter.
  private static func parameterBits(of parameter: MessageField, in commands: CommandSet) -> [GuardedBit] {

    guard case let .flags(fieldBits) = parameter.kind else {

      return []

    }

    return fieldBits.compactMap { (bit: FieldBit) -> GuardedBit? in

      rule(for: bit.writeGuard).map { (bitRule: Rule) -> GuardedBit in

        let label: String = commands.operatingFlag(named: bit.name).map { (flag: OperatingFlag) -> String in SettingItem(flag: flag).label } ?? bit.name.rawValue

        return GuardedBit(mask: bit.mask, label: label, rule: bitRule)

      }

    }

  }

  /// Every route the command set describes, with the guards on each, by route.
  package static func routeGuards(in commands: CommandSet) -> [ByteRoute: [RouteGuard]] {

    Dictionary(uniqueKeysWithValues: orderedRouteGuards(in: commands).map { (entry: (route: ByteRoute, guards: [RouteGuard])) -> (ByteRoute, [RouteGuard]) in (entry.route, entry.guards) })

  }

  /// Every route the command set describes, with the guards on each, in the command set's
  /// order: its extended settings writes and their bytes, then its extended commands and their
  /// parameters. A route's guards are the union of the guards of every value written on it,
  /// each with where it's read, and of every flags parameter bit on it. A route with no guards
  /// is listed with none, so its selector is known.
  package static func orderedRouteGuards(in commands: CommandSet) -> [(route: ByteRoute, guards: [RouteGuard])] {

    var routes: [ByteRoute: [RouteGuard]] = [:]
    var order: [ByteRoute] = []
    let settings: ExtendedSettings? = commands.extendedSettings

    func list(_ route: ByteRoute) {

      if routes[route] == nil {

        routes[route] = []
        order.append(route)

      }

    }

    func add(_ guardOnRoute: RouteGuard, to route: ByteRoute) {

      if !guardOnRoute.bits.isEmpty, routes[route]?.contains(guardOnRoute) != true {

        routes[route, default: []].append(guardOnRoute)

      }

    }

    for write in settings?.writes ?? [] {

      for byte in write.bytes {

        let route: ByteRoute = .extendedSet(selector: write.selector, position: byte.position)

        list(route)

        if let value = settings?.value(named: byte.value) {

          add(RouteGuard(readPosition: value.position, bits: flagsQueryBits(of: value, in: commands)), to: route)

        }

      }

    }

    for command in commands.extendedCommands {

      let written: [SettingValue] = (settings?.values ?? []).filter { (value: SettingValue) -> Bool in value.write == command.name }

      for parameter in command.parameters {

        let paramBits: [GuardedBit] = parameterBits(of: parameter, in: commands)
        let values: [SettingValue] = written.filter { (value: SettingValue) -> Bool in Self.parameter(of: command, for: value) == parameter }

        for position in parameter.positions {

          let route: ByteRoute = .extendedCommand(command.command, command.fixedBytes, position: position)

          list(route)

          // A value written through the parameter is read where the value is; a flags
          // parameter no value reads is reported nowhere.
          for value in values {

            add(RouteGuard(readPosition: value.position, bits: flagsQueryBits(of: value, in: commands) + paramBits), to: route)

          }

          if values.isEmpty {

            add(RouteGuard(readPosition: nil, bits: paramBits), to: route)

          }

        }

      }

    }

    return order.map { (route: ByteRoute) -> (route: ByteRoute, guards: [RouteGuard]) in (route, routes[route] ?? []) }

  }

  /// The routes a message writes, with the byte it writes on each: an extended Set's selector
  /// routes, and the routes of every extended command with its cmd1, cmd2 and fixed bytes, in
  /// the command set's order, each with its guards.
  package static func routes(writtenBy command: Command, userData: UserData, in routeGuards: [(route: ByteRoute, guards: [RouteGuard])]) -> [(route: ByteRoute, byte: UInt8, guards: [RouteGuard])] {

    routeGuards.compactMap { (entry: (route: ByteRoute, guards: [RouteGuard])) -> (route: ByteRoute, byte: UInt8, guards: [RouteGuard])? in

      let route: ByteRoute = entry.route

      switch route {
      case let .extendedSet(selector, position):
        return isExtendedSet(command, userData: userData) && userData[2] == selector ? (route, userData[position], entry.guards) : nil
      case let .extendedCommand(routeCommand, fixed, position):
        let matches: Bool = routeCommand == command && fixed.allSatisfy { (byte: FixedUserDataByte) -> Bool in userData[byte.position] == byte.value }
        return matches ? (route, userData[position], entry.guards) : nil
      }

    }

  }

  /// The guarded bit an extended message writes as its guard forbids, or `nil` if it writes
  /// none: every message a device is sent is checked here.
  ///
  /// With the device's report, as for a setting write, each guarded bit of every value or flags
  /// parameter on every route the message writes is checked against the byte written: a
  /// never-set bit may not be set, and a kept bit must match the byte as the device reported
  /// it, by where the value is read, or refuses the message if nothing reports it. Without the
  /// device's report, as for a message sent as given, a keep-awake message or a control
  /// action, any guarded bit, kept or never set, on a route the message writes refuses it,
  /// whatever the bit's value, and the first in the command set's order is named.
  ///
  /// - Parameters:
  ///   - command: The message's cmd1 and cmd2.
  ///   - userData: The message's user data.
  ///   - commands: The device's command set.
  ///   - current: The bytes the device reported, by their D position in the extended Get
  ///     reply, or `nil` if it wasn't asked.
  /// - Returns: The guarded bit, or `nil`.
  package static func guardViolation(by command: Command, userData: UserData, in commands: CommandSet, current: [Int: UInt8]?) -> GuardedBit? {

    for (_, byte, guards) in routes(writtenBy: command, userData: userData, in: orderedRouteGuards(in: commands)) {

      for guardOnRoute in guards {

        for bit in guardOnRoute.bits {

          // Without a report, a byte's bits can't be told from what the device holds.
          guard let current else {

            return bit

          }

          switch bit.rule {
          case .neverSet:
            if byte & bit.mask != 0 {

              return bit

            }
          case .keep:
            guard let position = guardOnRoute.readPosition, let reported = current[position], reported & bit.mask == byte & bit.mask else {

              return bit

            }
          }

        }

      }

    }

    return nil

  }

  /// The label of a guarded flag that an extended message sent as it's given writes, or `nil`
  /// if it writes none: ``guardViolation(by:userData:in:current:)`` with no report.
  package static func guardedFlagWritten(by command: Command, userData: UserData, in commands: CommandSet) -> String? {

    guardViolation(by: command, userData: userData, in: commands, current: nil)?.label

  }

  /// Whether a message is an extended Set whose selector the command set doesn't list, in an
  /// extended settings write or an extended command's fixed D2, so which bytes it writes
  /// can't be told.
  package static func isUnlistedExtendedSet(_ command: Command, userData: UserData, in commands: CommandSet) -> Bool {

    guard isExtendedSet(command, userData: userData) else {

      return false

    }

    let selector: UInt8 = userData[2]
    let isWrite: Bool = commands.extendedSettings?.writes.contains { (write: SettingWrite) -> Bool in write.selector == selector } ?? false
    let isCommand: Bool = commands.extendedCommands.contains { (extended: DeviceExtendedCommand) -> Bool in

      extended.command == command && extended.fixedBytes.contains { (byte: FixedUserDataByte) -> Bool in byte.position == 2 && byte.value == selector }

    }

    return !isWrite && !isCommand

  }

  /// Whether a message is an extended Set: cmd1 `0x2E` and cmd2 `0x00` with a selector other
  /// than `0x00` in D2, which writes whatever bytes the device's selector names.
  package static func isExtendedSet(_ command: Command, userData: UserData) -> Bool {

    command == Command(command1: 0x2E, command2: 0x00) && userData[2] != 0x00

  }

  /// The parameter of an extended command a value is written into: the value's own, or else
  /// the command's only one, as `ValueChange.message(to:button:setting:to:current:)` chooses it.
  package static func parameter(of command: DeviceExtendedCommand, for value: SettingValue) -> MessageField? {

    let named: MessageField? = command.parameters.first { (field: MessageField) -> Bool in field.name == value.name }

    return named ?? (command.parameters.count == 1 ? command.parameters.first : nil)

  }

}
