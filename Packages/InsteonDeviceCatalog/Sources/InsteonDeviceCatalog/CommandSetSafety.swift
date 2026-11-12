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

  /// Whether a message matches a command the command set marks ``CommandGuard/never``, whatever
  /// its cmd1: a standard command by its cmd1 and cmd2, or by its cmd1 when a parameter fills
  /// cmd2, and an extended command by its cmd1, cmd2 and fixed bytes, the reading the guards'
  /// routes use. A standard message matches an extended command by its cmd1 and cmd2.
  ///
  /// - Parameters:
  ///   - command: The message's cmd1 and cmd2.
  ///   - userData: An extended message's user data, or `nil` for a standard message.
  ///   - commands: The device's command set, or `nil` if the catalog gives it none.
  package static func matchesNeverSentEntry(_ command: Command, userData: UserData?, in commands: CommandSet?) -> Bool {

    guard let commands else {

      return false

    }

    for standard in commands.standardCommands where isNeverSent(standard.sendGuard) && sends(standard, as: command, userData: nil) {

      return true

    }

    for extended in commands.extendedCommands where isNeverSent(extended.sendGuard) && extended.command == command {

      let fixed: Bool = userData.map { (data: UserData) -> Bool in

        extended.fixedBytes.allSatisfy { (byte: FixedUserDataByte) -> Bool in data[byte.position] == byte.value }

      } ?? true

      if fixed {

        return true

      }

    }

    return false

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

  /// An extended command's fixed bytes as a route or command key: in D order, each position
  /// once, the last given winning, and without the bytes its integrity check overwrites, so
  /// two commands that send the same bytes have the same key.
  package static func keyBytes(of command: DeviceExtendedCommand) -> [FixedUserDataByte] {

    let reserved: Set<Int>

    switch command.integrity {
    case .unprotected:
      reserved = []
    case .checksum:
      reserved = [14]
    case .crc:
      reserved = [13, 14]
    }

    var byPosition: [Int: UInt8] = [:]

    for byte in command.fixedBytes where !reserved.contains(byte.position) {

      byPosition[byte.position] = byte.value

    }

    return byPosition.keys.sorted().map { (position: Int) -> FixedUserDataByte in FixedUserDataByte(position: position, value: byPosition[position] ?? 0) }

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

          let route: ByteRoute = .extendedCommand(command.command, keyBytes(of: command), position: position)

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

  /// What a message does to the device it's sent to, as the device's command set describes it
  /// by the message's bytes.
  package enum MessageEffect: Hashable, Sendable {

    /// One or more entries describe the message: the strictest of their effects, and whether
    /// every one of them is idempotent.
    case described(CommandEffect, isIdempotent: Bool)

    /// No entry describes the message.
    case undescribed

  }

  /// What a message does to a device that uses a command set, found by its bytes rather than
  /// the name it's sent under, so it can't change its effect by being sent as another command.
  ///
  /// A standard message matches a standard command by cmd1 and its fixed cmd2, or any cmd2 its
  /// parameter allows: one an enumeration names, or any for another kind. A Set Operating Flags
  /// message (cmd1 `0x20`), standard or extended, matches a flag command and an operating
  /// flag's on or off by cmd2, the flag's on and off as ``CommandEffect/configuration`` and
  /// idempotent. An extended message matches:
  ///
  /// - an extended command by cmd1, cmd2 and every user data byte: a fixed byte holds its
  ///   value, a byte a parameter fills, D1 of a per-button command and the integrity bytes hold
  ///   any value, and every other byte is `0x00`;
  /// - an extended settings write, as ``CommandEffect/configuration`` and idempotent, by cmd1
  ///   `0x2E`, cmd2 `0x00` and the write's selector in D2;
  /// - a standard command, in the form ``DeviceStandardCommand/extendedWhen`` sends: its cmd1
  ///   and cmd2 again in D1 and D2 and `0x00` in D3 through D12, with D13 and D14 left to an
  ///   integrity check.
  ///
  /// It fails closed: an entry without an effect, or with one this package doesn't know, is
  /// ``CommandEffect/destructive``, and one without `idempotent` isn't idempotent. A message
  /// several entries describe takes the strictest of their effects, and two different effects
  /// of the same ``CommandEffect/Strictness``, such as link and actuation, read as destructive,
  /// since neither stands for the other. It's idempotent only if every entry is.
  ///
  /// - Parameters:
  ///   - command: The message's cmd1 and cmd2.
  ///   - userData: An extended message's user data, or `nil` for a standard message.
  ///   - commands: The device's command set, or `nil` if the catalog gives it none.
  /// - Returns: The effect, or ``MessageEffect/undescribed`` if no entry describes the message,
  ///   as for every message to a device without a command set.
  package static func effect(of command: Command, userData: UserData?, in commands: CommandSet?) -> MessageEffect {

    matchedEffect(of: command, userData: userData, in: commands, isLoose: false)

  }

  /// What a message does to a device, read the way a send is authorized: the strictest effect of
  /// every entry ``effect(of:userData:in:)`` matches and every entry that matches loosely.
  ///
  /// A loose match is by cmd1, cmd2 and an extended command's fixed bytes alone, the reading the
  /// guards' routes use, so a byte the entry doesn't fix, such as a checksum an entry without
  /// one doesn't carry or padding after the fixed bytes, can't make a message read as
  /// undescribed. A standard message matches an extended command by its cmd1 and cmd2, and an
  /// extended message a standard command the same way. Every strict match is a loose match, so
  /// this reads a message as strictly as ``effect(of:userData:in:)`` does or more. A message
  /// is undescribed only when neither matches any entry.
  ///
  /// - Parameters:
  ///   - command: The message's cmd1 and cmd2.
  ///   - userData: An extended message's user data, or `nil` for a standard message.
  ///   - commands: The device's command set, or `nil` if the catalog gives it none.
  /// - Returns: The effect, or ``MessageEffect/undescribed``.
  package static func authorizationEffect(of command: Command, userData: UserData?, in commands: CommandSet?) -> MessageEffect {

    matchedEffect(of: command, userData: userData, in: commands, isLoose: true)

  }

  /// What a serial frame does to a modem that uses a command set, found by the frame's command
  /// number and payload bytes, read the way a send is authorized.
  ///
  /// A serial command matches a frame by its number and every fixed payload byte; a byte a
  /// parameter fills holds any value. A frame cut short of a fixed byte matches nothing. A frame
  /// several entries match takes the strictest of their effects, two different effects of the
  /// same ``CommandEffect/Strictness`` reading as destructive, and is idempotent only if every
  /// entry is. An entry without an effect, or with one this package doesn't know, is
  /// ``CommandEffect/destructive``, and one without `idempotent` isn't idempotent.
  ///
  /// - Parameters:
  ///   - number: The frame's command number, the byte after `0x02`.
  ///   - payload: The bytes after the number.
  ///   - commands: The modem's command set, or `nil` if the catalog gives it none.
  /// - Returns: The effect, or ``MessageEffect/undescribed`` if no entry describes the frame, as
  ///   for every frame to a modem without a command set.
  package static func serialEffect(number: UInt8, payload: [UInt8], in commands: CommandSet?) -> MessageEffect {

    guard let commands else {

      return .undescribed

    }

    let matched: [DeviceSerialCommand] = commands.serialCommands.filter { (command: DeviceSerialCommand) -> Bool in

      command.number == number && command.fixedBytes.allSatisfy { (byte: FixedPayloadByte) -> Bool in

        byte.position <= payload.count && payload[byte.position - 1] == byte.value

      }

    }

    guard let first = matched.first else {

      return .undescribed

    }

    let effect: CommandEffect = matched.dropFirst().reduce(reading(first.effect)) { (strictest: CommandEffect, command: DeviceSerialCommand) -> CommandEffect in

      stricter(strictest, reading(command.effect))

    }

    return .described(effect, isIdempotent: matched.allSatisfy { (command: DeviceSerialCommand) -> Bool in command.isIdempotent == true })

  }

  /// Whether the modem's command set marks a serial frame as never sent: an entry the frame
  /// matches by number and fixed payload bytes has ``CommandGuard/never``.
  ///
  /// - Parameters:
  ///   - number: The frame's command number.
  ///   - payload: The bytes after the number.
  ///   - commands: The modem's command set, or `nil`.
  /// - Returns: `true` if an app never sends the frame.
  package static func isSerialNeverSent(number: UInt8, payload: [UInt8], in commands: CommandSet?) -> Bool {

    (commands?.serialCommands ?? []).contains { (command: DeviceSerialCommand) -> Bool in

      isNeverSent(command.sendGuard) && command.number == number && command.fixedBytes.allSatisfy { (byte: FixedPayloadByte) -> Bool in

        byte.position <= payload.count && payload[byte.position - 1] == byte.value

      }

    }

  }

  private static func matchedEffect(of command: Command, userData: UserData?, in commands: CommandSet?, isLoose: Bool) -> MessageEffect {

    guard let commands else {

      return .undescribed

    }

    var matched: [(effect: CommandEffect?, isIdempotent: Bool?)] = []

    if command.command1 == setOperatingFlagsCommand1 {

      for flag in commands.operatingFlags where flag.on == command.command2 || flag.off == command.command2 {

        matched.append((effect: .configuration, isIdempotent: true))

      }

      for flagCommand in commands.flagCommands where flagCommand.command.command == command {

        matched.append((effect: flagCommand.effect, isIdempotent: flagCommand.isIdempotent))

      }

    }

    for standard in commands.standardCommands where sends(standard, as: command, userData: isLoose ? nil : userData) {

      matched.append((effect: standard.effect, isIdempotent: standard.isIdempotent))

    }

    if isLoose {

      for extended in commands.extendedCommands where extended.command == command && (userData.map { (data: UserData) -> Bool in extended.fixedBytes.allSatisfy { (byte: FixedUserDataByte) -> Bool in data[byte.position] == byte.value } } ?? true) {

        matched.append((effect: extended.effect, isIdempotent: extended.isIdempotent))

      }

    }

    if let userData {

      for extended in commands.extendedCommands where !isLoose && sends(extended, as: command, userData: userData) {

        matched.append((effect: extended.effect, isIdempotent: extended.isIdempotent))

      }

      if command == Command(command1: 0x2E, command2: 0x00) {

        for write in commands.extendedSettings?.writes ?? [] where write.selector == userData[2] {

          matched.append((effect: .configuration, isIdempotent: true))

        }

      }

    }

    guard let first = matched.first else {

      return .undescribed

    }

    let effect: CommandEffect = matched.dropFirst().reduce(reading(first.effect)) { (strictest: CommandEffect, entry: (effect: CommandEffect?, isIdempotent: Bool?)) -> CommandEffect in

      stricter(strictest, reading(entry.effect))

    }

    let isIdempotent: Bool = matched.allSatisfy { (entry: (effect: CommandEffect?, isIdempotent: Bool?)) -> Bool in entry.isIdempotent == true }

    return .described(effect, isIdempotent: isIdempotent)

  }

  /// An entry's effect as ``effect(of:userData:in:)`` reads it: one that's missing, or that
  /// this package doesn't know, is destructive.
  private static func reading(_ effect: CommandEffect?) -> CommandEffect {

    guard let effect, effect.strictness != .destructive else {

      return .destructive

    }

    return effect

  }

  /// The stricter of two effects this package knows, or destructive for two different ones of
  /// the same strictness.
  private static func stricter(_ left: CommandEffect, _ right: CommandEffect) -> CommandEffect {

    if left.strictness != right.strictness {

      return left.strictness > right.strictness ? left : right

    }

    return left == right ? left : .destructive

  }

  /// Whether a message is a standard command: as a standard message, by cmd1 and its fixed cmd2
  /// or one its parameter allows, or as an extended message in the form its `extendedWhen`
  /// sends.
  private static func sends(_ standard: DeviceStandardCommand, as command: Command, userData: UserData?) -> Bool {

    guard standard.command1 == command.command1 else {

      return false

    }

    switch standard.command2 {
    case let .fixed(command2):
      guard command2 == command.command2 else {

        return false

      }
    case let .parameter(field):
      if case let .enumeration(enumeration) = field.kind, enumeration.name(for: command.command2) == nil {

        return false

      }
    }

    guard let userData else {

      return true

    }

    // The extended form: cmd1 and cmd2 again in D1 and D2, and 0x00 up to the integrity bytes,
    // which the widest integrity check, a CRC, puts in D13 and D14.
    return userData[1] == command.command1 && userData[2] == command.command2 && (3...12).allSatisfy { (position: Int) -> Bool in userData[position] == 0x00 }

  }

  /// Whether an extended message is an extended command: its cmd1 and cmd2, each fixed byte's
  /// value, any value in a byte a parameter fills, in D1 of a per-button command and in the
  /// integrity bytes, and `0x00` in every other byte.
  private static func sends(_ extended: DeviceExtendedCommand, as command: Command, userData: UserData) -> Bool {

    guard extended.command == command else {

      return false

    }

    // Each D position's expected value, by position, or nil for any value; index 0 is unused.
    var expected: [UInt8?] = Array(repeating: 0x00, count: UserData.count + 1)

    for parameter in extended.parameters {

      for position in parameter.positions {

        expected[position] = nil

      }

    }

    if extended.isPerButton {

      expected[1] = nil

    }

    switch extended.integrity {
    case .unprotected:
      break
    case .checksum:
      expected[14] = nil
    case .crc:
      expected[13] = nil
      expected[14] = nil
    }

    // A fixed byte holds its value even where a parameter or a per-button D1 would fill it, as
    // the catalog's build reads it.
    for byte in extended.fixedBytes {

      expected[byte.position] = byte.value

    }

    return (1...UserData.count).allSatisfy { (position: Int) -> Bool in expected[position].map { (value: UInt8) -> Bool in userData[position] == value } ?? true }

  }

  /// The parameter of an extended command a value is written into: the value's own, or else
  /// the command's only one, as `ValueChange.message(to:button:setting:to:current:)` chooses it.
  package static func parameter(of command: DeviceExtendedCommand, for value: SettingValue) -> MessageField? {

    let named: MessageField? = command.parameters.first { (field: MessageField) -> Bool in field.name == value.name }

    return named ?? (command.parameters.count == 1 ? command.parameters.first : nil)

  }

}
