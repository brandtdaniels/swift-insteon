import InsteonProtocol

/// A guard that a catalog gives more weakly than a baseline catalog, such as the copy the
/// package ships with, for a command set both have.
///
/// The guards keep a device reachable and unlocked, so a catalog an app loads in place of the
/// bundled copy, downloaded or saved, may add guards but never weaken one.
/// ``DeviceCatalog/guardWeakenings(comparedTo:)`` finds them:
///
/// ```swift
/// let weakenings = downloaded.guardWeakenings(comparedTo: try DeviceCatalog.bundled())
///
/// if !weakenings.isEmpty {
///   print("Keeping the bundled catalog:", weakenings)
/// }
/// ```
public struct GuardWeakening: Hashable, Sendable, CustomStringConvertible {

  /// What kind of guard is weakened.
  public enum Kind: String, Hashable, Sendable {

    /// An operating flag's ``FlagGuard``.
    case flag

    /// The ``FlagGuard`` of a bit of an extended command's flags parameter.
    case flagsBit

    /// A flag, standard or extended command's ``CommandGuard``.
    case command

    /// An extended settings value's ``SettingValue/flagsQuery``.
    case flagsQuery

  }

  /// The command set both catalogs have.
  public var commandSet: CommandSetID

  /// What kind of guard is weakened.
  public var kind: Kind

  /// The flag, bit, command or value, by its name in the baseline catalog.
  public var name: SettingName

  /// Creates a weakened guard.
  ///
  /// - Parameters:
  ///   - commandSet: The command set both catalogs have.
  ///   - kind: What kind of guard is weakened.
  ///   - name: The flag, bit, command or value, by its name in the baseline catalog.
  public init(commandSet: CommandSetID, kind: Kind, name: SettingName) {

    self.commandSet = commandSet
    self.kind = kind
    self.name = name

  }

  /// The guard as `commandSet kind name`, such as `exampleSwitch flag lockout`.
  public var description: String { "\(commandSet) \(kind.rawValue) \(name)" }

}

extension DeviceCatalog {

  /// The guards this catalog gives more weakly than a baseline, for each command set id both
  /// catalogs have. A command set only one of them has isn't compared.
  ///
  /// A guard is weakened when, in the same command set:
  /// - a flag the baseline guards is missing, or a flag with its name or its query and bit, or
  ///   with a Set Operating Flags cmd2 the baseline's guard covers, has a weaker guard: no
  ///   guard is weaker than `neverSet`, which is weaker than `keep` or a guard this package
  ///   doesn't know;
  /// - a guarded bit of an extended command's flags parameter is missing or has a weaker
  ///   guard;
  /// - a command the baseline guards is missing or has no guard, or another command with its
  ///   Set Operating Flags bytes has none;
  /// - a value the baseline marks with a ``SettingValue/flagsQuery`` is missing, or a value
  ///   with its name or position has another query or none.
  ///
  /// - Parameter baseline: The catalog whose guards are the least this one gives, such as
  ///   ``DeviceCatalog/bundled()``.
  /// - Returns: The weakened guards, in the baseline's order, or none.
  public func guardWeakenings(comparedTo baseline: DeviceCatalog) -> [GuardWeakening] {

    baseline.commandSets.flatMap { (old: CommandSet) -> [GuardWeakening] in

      commandSet(id: old.id).map { (new: CommandSet) -> [GuardWeakening] in Self.weakenings(of: old, in: new) } ?? []

    }

  }

  /// How strict a flag guard is: none, never set, then kept, with a guard this package doesn't
  /// know as strict as kept.
  static func strictness(_ writeGuard: FlagGuard?) -> Int {

    switch writeGuard {
    case nil:
      0
    case .neverSet?:
      1
    case _?:
      2
    }

  }

  /// The guards of one command set that another version of it weakens.
  static func weakenings(of old: CommandSet, in new: CommandSet) -> [GuardWeakening] {

    var found: [GuardWeakening] = []

    func add(_ kind: GuardWeakening.Kind, _ name: SettingName) {

      let weakening = GuardWeakening(commandSet: old.id, kind: kind, name: name)

      if !found.contains(weakening) {

        found.append(weakening)

      }

    }

    for flag in old.operatingFlags where flag.writeGuard != nil {

      let strictness: Int = Self.strictness(flag.writeGuard)
      let isKept: Bool = strictness > 1

      if new.operatingFlag(named: flag.name) == nil {

        add(.flag, flag.name)

      }

      for candidate in new.operatingFlags where Self.strictness(candidate.writeGuard) < strictness {

        let sameFlag: Bool = candidate.name == flag.name || (candidate.query == flag.query && candidate.bit == flag.bit)
        let sameOn: Bool = flag.on != nil && candidate.on == flag.on
        let sameOff: Bool = isKept && flag.off != nil && candidate.off == flag.off

        if sameFlag || sameOn || sameOff {

          add(.flag, flag.name)

        }

      }

    }

    for command in old.extendedCommands {

      for parameter in command.parameters {

        guard case let .flags(bits) = parameter.kind else {

          continue

        }

        let newBits: [FieldBit] = new.extendedCommand(named: command.name)?.parameters
          .first { (field: MessageField) -> Bool in field.name == parameter.name }
          .map { (field: MessageField) -> [FieldBit] in

            if case let .flags(newBits) = field.kind {

              return newBits

            }

            return []

          } ?? []

        for bit in bits where bit.writeGuard != nil {

          let matching: [FieldBit] = newBits.filter { (other: FieldBit) -> Bool in other.mask == bit.mask || other.name == bit.name }

          if matching.isEmpty || matching.contains(where: { (other: FieldBit) -> Bool in Self.strictness(other.writeGuard) < Self.strictness(bit.writeGuard) }) {

            add(.flagsBit, bit.name)

          }

        }

      }

    }

    let oldCommands: [GuardedCommand] = Self.commands(of: old)
    let newCommands: [GuardedCommand] = Self.commands(of: new)

    for command in oldCommands where command.isGuarded {

      let sameName: [GuardedCommand] = newCommands.filter { (other: GuardedCommand) -> Bool in other.kind == command.kind && other.name == command.name }
      let sameBytes: [GuardedCommand] = command.setOperatingFlags.map { (bytes: Command) -> [GuardedCommand] in

        newCommands.filter { (other: GuardedCommand) -> Bool in other.setOperatingFlags == bytes }

      } ?? []

      if sameName.isEmpty || (sameName + sameBytes).contains(where: { (other: GuardedCommand) -> Bool in !other.isGuarded }) {

        add(.command, command.name)

      }

    }

    for value in old.extendedSettings?.values ?? [] {

      guard let query = value.flagsQuery else {

        continue

      }

      let newValues: [SettingValue] = new.extendedSettings?.values ?? []
      let matching: [SettingValue] = newValues.filter { (other: SettingValue) -> Bool in other.name == value.name || other.position == value.position }

      if !newValues.contains(where: { (other: SettingValue) -> Bool in other.name == value.name })
        || matching.contains(where: { (other: SettingValue) -> Bool in other.flagsQuery != query }) {

        add(.flagsQuery, value.name)

      }

    }

    return found

  }

  /// A flag, standard or extended command, with its guard and its Set Operating Flags bytes.
  struct GuardedCommand {

    /// Which list of the command set the command is in.
    enum Kind {

      case flag
      case standard
      case extended

    }

    let kind: Kind

    let name: SettingName

    let isGuarded: Bool

    /// The command's bytes when it's Set Operating Flags (cmd1 `0x20`) with a fixed cmd2.
    let setOperatingFlags: Command?

  }

  /// Every flag, standard and extended command of a command set.
  static func commands(of commands: CommandSet) -> [GuardedCommand] {

    let setOperatingFlags: UInt8 = 0x20

    func ifSetOperatingFlags(_ command: Command) -> Command? {

      command.command1 == setOperatingFlags ? command : nil

    }

    let flags: [GuardedCommand] = commands.flagCommands.map { (command: OperatingFlagCommand) -> GuardedCommand in

      GuardedCommand(kind: .flag, name: command.name, isGuarded: command.sendGuard != nil, setOperatingFlags: ifSetOperatingFlags(command.command.command))

    }
    let standards: [GuardedCommand] = commands.standardCommands.map { (command: DeviceStandardCommand) -> GuardedCommand in

      var bytes: Command?

      if case let .fixed(command2) = command.command2 {

        bytes = ifSetOperatingFlags(Command(command1: command.command1, command2: command2))

      }

      return GuardedCommand(kind: .standard, name: command.name, isGuarded: command.sendGuard != nil, setOperatingFlags: bytes)

    }
    let extendeds: [GuardedCommand] = commands.extendedCommands.map { (command: DeviceExtendedCommand) -> GuardedCommand in

      GuardedCommand(kind: .extended, name: command.name, isGuarded: command.sendGuard != nil, setOperatingFlags: ifSetOperatingFlags(command.command))

    }

    return flags + standards + extendeds

  }

}

extension DeviceCatalog {

  /// Throws if this catalog gives any guard more weakly than a baseline, as
  /// ``guardWeakenings(comparedTo:)`` finds them, so an app keeps using the baseline.
  ///
  /// - Parameter baseline: The catalog whose guards are the least this one gives, such as
  ///   ``DeviceCatalog/bundled()``.
  /// - Throws: ``DeviceCatalogError/weakensGuards(_:)`` with the weakened guards.
  public func checkGuards(against baseline: DeviceCatalog) throws {

    let weakenings: [GuardWeakening] = guardWeakenings(comparedTo: baseline)

    guard weakenings.isEmpty else {

      throw DeviceCatalogError.weakensGuards(weakenings)

    }

  }

}
