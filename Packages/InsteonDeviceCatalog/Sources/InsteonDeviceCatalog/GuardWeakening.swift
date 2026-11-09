import InsteonProtocol

/// A way a catalog would let an app send or write more to a device than a baseline catalog,
/// such as the copy the package ships with, lets it.
///
/// The guards keep a device reachable and unlocked, so a catalog an app loads in place of the
/// bundled copy, downloaded or saved, may make them stricter but never weaker for a device the
/// bundled copy knows. ``DeviceCatalog/guardWeakenings(comparedTo:)`` finds where it would:
///
/// ```swift
/// let weakenings = downloaded.guardWeakenings(comparedTo: try DeviceCatalog.bundled())
///
/// if !weakenings.isEmpty {
///   print("Keeping the bundled catalog:", weakenings)
/// }
/// ```
public struct GuardWeakening: Hashable, Sendable, CustomStringConvertible {

  /// What the catalog would let through that the baseline doesn't.
  public enum Kind: String, Hashable, Sendable {

    /// Bytes the baseline never sends to the device, which the catalog would send.
    case sendsNeverSentBytes

    /// A protected Set Operating Flags cmd2 the baseline keeps refused, which the catalog
    /// would send because its command set names it through an unguarded flag or command.
    case unlocksProtectedCommand

    /// Bits of an operating flags byte the baseline keeps or never sets, which the catalog
    /// guards less.
    case flagBits

    /// Bits of an extended command's flags parameter the baseline keeps or never sets, which
    /// the catalog guards less.
    case parameterBits

    /// Bits of an extended settings value's byte that a write of the value keeps or never sets
    /// in the baseline, which the catalog guards less, such as when another command writes it.
    case valueBits

    /// A value whose byte the baseline marks as an operating flags byte, which the catalog
    /// doesn't mark with the same query.
    case flagsQuery

    /// An extended Set selector whose bytes hold guarded flags in the baseline but not in the
    /// catalog.
    case writeSelector

    /// A command the baseline guards, whose bytes the catalog sends with no guard.
    case commandGuard

  }

  /// The category of the device it's for.
  public var category: DeviceCategory

  /// The subcategory of the device it's for.
  public var subcategory: DeviceSubcategory

  /// The first firmware version it's found for, or `nil` for a device that reports none.
  public var firmwareVersion: FirmwareVersion?

  /// What the catalog would let through.
  public var kind: Kind

  /// The bytes, bits or selector, such as `Set Operating Flags 0x0C`.
  public var detail: String

  /// Creates a weakened guard.
  ///
  /// - Parameters:
  ///   - category: The category of the device it's for.
  ///   - subcategory: The subcategory of the device it's for.
  ///   - firmwareVersion: The first firmware version it's found for, or `nil` for a device
  ///     that reports none.
  ///   - kind: What the catalog would let through.
  ///   - detail: The bytes, bits or selector.
  public init(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?, kind: Kind, detail: String) {

    self.category = category
    self.subcategory = subcategory
    self.firmwareVersion = firmwareVersion
    self.kind = kind
    self.detail = detail

  }

  /// The weakened guard as one phrase, such as
  /// `0x01/0x24 sendsNeverSentBytes Set Operating Flags 0x0C`.
  public var description: String { "\(category)/\(subcategory) \(kind.rawValue) \(detail)" }

}

extension DeviceCatalog {

  /// Where this catalog would let an app send or write more to a device than a baseline does.
  ///
  /// For every category and subcategory a profile of the baseline has an identity for, and
  /// for every firmware version `0x00` through `0xFF` and none, each catalog's command set for
  /// that device is found as an app finds it, whatever its id, and summarized with the rules
  /// InsteonCore applies when it sends (`CommandSetSafety`): the bytes it never sends, the
  /// protected Set Operating Flags cmd2s it unlocks, the operating flag and flags parameter
  /// bits it keeps or never sets, the values it marks as operating flags bytes, the extended
  /// Set selectors that write guarded flags, and the commands it guards. This catalog is at
  /// least as strict when it never sends every byte the baseline never sends, unlocks no
  /// protected cmd2 the baseline keeps refused, guards every bit the baseline guards at least
  /// as strictly, marks every flags byte the baseline marks with the same query, and sends no
  /// bytes the baseline guards from an unguarded command. A device the baseline knows that
  /// this catalog gives no command set is compared as having no guards. A device only this
  /// catalog knows isn't compared.
  ///
  /// - Parameter baseline: The catalog whose guards are the least this one gives, such as
  ///   ``DeviceCatalog/bundled()``.
  /// - Returns: Each way it's weaker, once per device, kind and detail, ordered by category
  ///   and subcategory; none when it's at least as strict.
  public func guardWeakenings(comparedTo baseline: DeviceCatalog) -> [GuardWeakening] {

    let firmwareVersions: [FirmwareVersion?] = [nil] + (UInt8.min...UInt8.max).map { (version: UInt8) -> FirmwareVersion? in FirmwareVersion(rawValue: version) }
    let identities = baseline.indexedIdentities.sorted { (left, right) -> Bool in

      (left.category.rawValue, left.subcategory.rawValue) < (right.category.rawValue, right.subcategory.rawValue)

    }
    let oldByID: [CommandSetID: CommandSet] = Self.commandSetsByID(baseline)
    let newByID: [CommandSetID: CommandSet] = Self.commandSetsByID(self)
    var oldSummaries: [CommandSetID: SafetySummary] = [:]
    var newSummaries: [CommandSetID: SafetySummary] = [:]
    var comparisons: [CommandSetPair: [Finding]] = [:]
    var weakenings: [GuardWeakening] = []

    func summary(of commands: CommandSet?, in cache: inout [CommandSetID: SafetySummary]) -> SafetySummary {

      guard let commands else {

        return SafetySummary(nil)

      }

      if let known = cache[commands.id] {

        return known

      }

      let made = SafetySummary(commands)

      cache[commands.id] = made

      return made

    }

    for identity in identities {

      var found: Set<Finding> = []
      // With no profile narrowed to some firmware in either catalog, every version finds what
      // a device that reports none finds.
      let isNarrowed: Bool = baseline.selectsByFirmware(category: identity.category, subcategory: identity.subcategory)
        || selectsByFirmware(category: identity.category, subcategory: identity.subcategory)

      for firmware in isNarrowed ? firmwareVersions : [nil] {

        let old: CommandSet? = baseline.commandSet(category: identity.category, subcategory: identity.subcategory, firmwareVersion: firmware, byID: oldByID)
        let new: CommandSet? = commandSet(category: identity.category, subcategory: identity.subcategory, firmwareVersion: firmware, byID: newByID)
        let pair = CommandSetPair(old: old?.id, new: new?.id)
        let findings: [Finding]

        if let known = comparisons[pair] {

          findings = known

        } else {

          findings = summary(of: new, in: &newSummaries).weakenings(comparedTo: summary(of: old, in: &oldSummaries))
          comparisons[pair] = findings

        }

        for finding in findings where found.insert(finding).inserted {

          weakenings.append(GuardWeakening(category: identity.category, subcategory: identity.subcategory, firmwareVersion: firmware, kind: finding.kind, detail: finding.detail))

        }

      }

    }

    return weakenings

  }

  /// A catalog's command sets by their ids, the first of each id, as ``commandSet(id:)`` finds
  /// it.
  static func commandSetsByID(_ catalog: DeviceCatalog) -> [CommandSetID: CommandSet] {

    var byID: [CommandSetID: CommandSet] = [:]

    for commands in catalog.commandSets where byID[commands.id] == nil {

      byID[commands.id] = commands

    }

    return byID

  }

  /// The command set of a device, as ``commandSet(category:subcategory:firmwareVersion:)``
  /// finds it, with the command sets looked up by id.
  func commandSet(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?, byID: [CommandSetID: CommandSet]) -> CommandSet? {

    guard
      let profile = profile(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion),
      let entry = profile.commandSets.first(where: { (entry: CommandSetEntry) -> Bool in entry.covers(category: category, subcategory: subcategory, firmwareVersion: firmwareVersion) })
    else {

      return nil

    }

    return byID[entry.commandSet]

  }

  /// Throws if this catalog would let an app send or write more to any device than a baseline
  /// does, as ``guardWeakenings(comparedTo:)`` finds it, so an app keeps using the baseline.
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

/// The ids of the command sets a device has in each catalog, or `nil` for none.
private struct CommandSetPair: Hashable {

  let old: CommandSetID?

  let new: CommandSetID?

}

/// One way a command set is weaker than another, before it's tied to a device.
private struct Finding: Hashable {

  let kind: GuardWeakening.Kind

  let detail: String

}

/// A byte as `0x0C`.
private func hex(_ byte: UInt8) -> String {

  let digits: String = String(byte, radix: 16, uppercase: true)

  return "0x" + (digits.count == 1 ? "0" : "") + digits

}

/// What the send-time rules of `CommandSetSafety` make of a command set, or of a device with
/// none, which only the byte floor guards.
struct SafetySummary: Hashable {

  /// Where a guarded bit is: an operating flags byte by its query, or an extended command's
  /// flags parameter by the command's bytes, its fixed bytes and the parameter's location.
  enum BitsKey: Hashable {

    case query(OperatingFlagsRequest)

    case parameter(Command, [FixedUserDataByte], FieldLocation)

    /// An extended settings value's byte, by its position, through whatever command writes it.
    case value(Int)

  }

  /// A command by the bytes it sends: a standard message's cmd1 and its fixed cmd2, if any,
  /// or an extended message's cmd1, cmd2 and fixed bytes.
  enum CommandKey: Hashable {

    case standard(UInt8, UInt8?)

    case extended(Command, [FixedUserDataByte])

  }

  /// The bytes never sent, the byte floor's included.
  var neverSent: Set<Command> = []

  /// The protected Set Operating Flags cmd2s the command set unlocks.
  var unlockedFloor: Set<UInt8> = []

  /// The kept bits, by where they are.
  var keptBits: [BitsKey: UInt8] = [:]

  /// The never-set bits, by where they are.
  var neverSetBits: [BitsKey: UInt8] = [:]

  /// The query of each value whose byte is an operating flags byte, by its position.
  var flagsQueries: [Int: OperatingFlagsRequest] = [:]

  /// The extended Set selectors that write a byte holding guarded flags.
  var guardedSelectors: Set<UInt8> = []

  /// The commands guarded, and those not, by their bytes.
  var guardedCommands: Set<CommandKey> = []

  var unguardedCommands: Set<CommandKey> = []

  init(_ commands: CommandSet?) {

    neverSent = CommandSetSafety.neverSentCommands(in: commands)

    // A protected cmd2 is unlocked when the command set never refuses it, by the floor or by a
    // guard.
    unlockedFloor = Set(CommandSetSafety.protectedSetOperatingFlags.subtracting(neverSent).map(\.command2))

    guard let commands else {

      return

    }

    func addBits(_ mask: UInt8, at key: BitsKey, rule: CommandSetSafety.Rule) {

      switch rule {
      case .keep:
        keptBits[key, default: 0] |= mask
      case .neverSet:
        neverSetBits[key, default: 0] |= mask
      }

    }

    for flag in commands.operatingFlags {

      if let rule = CommandSetSafety.rule(for: flag) {

        addBits(flag.bit, at: .query(flag.query), rule: rule)

      }

    }

    for command in commands.extendedCommands {

      for parameter in command.parameters {

        guard case let .flags(bits) = parameter.kind else {

          continue

        }

        for bit in bits {

          if let rule = CommandSetSafety.rule(for: bit.writeGuard) {

            addBits(bit.mask, at: .parameter(command.command, command.fixedBytes, parameter.location), rule: rule)

          }

        }

      }

    }

    let settings: ExtendedSettings? = commands.extendedSettings

    for value in settings?.values ?? [] {

      if let query = value.flagsQuery {

        flagsQueries[value.position] = query

      }

      // The bits a write of the value guards, as the write itself finds them.
      for bit in CommandSetSafety.guardedBits(in: value, of: commands) {

        addBits(bit.mask, at: .value(value.position), rule: bit.rule)

      }

    }

    for write in settings?.writes ?? [] {

      let isGuarded: Bool = write.bytes.contains { (byte: SettingWrite.Byte) -> Bool in

        settings?.value(named: byte.value).map { (value: SettingValue) -> Bool in !CommandSetSafety.guardedBits(in: value, of: commands).isEmpty } ?? false

      }

      if isGuarded {

        guardedSelectors.insert(write.selector)

      }

    }

    func add(_ key: CommandKey, isGuarded: Bool) {

      if isGuarded {

        guardedCommands.insert(key)

      } else {

        unguardedCommands.insert(key)

      }

    }

    for command in commands.flagCommands {

      add(.standard(command.command.command.command1, command.command.command.command2), isGuarded: CommandSetSafety.isNeverSent(command.sendGuard))

    }

    for command in commands.standardCommands {

      var command2: UInt8?

      if case let .fixed(fixed) = command.command2 {

        command2 = fixed

      }

      add(.standard(command.command1, command2), isGuarded: CommandSetSafety.isNeverSent(command.sendGuard))

    }

    for command in commands.extendedCommands {

      add(.extended(command.command, command.fixedBytes), isGuarded: CommandSetSafety.isNeverSent(command.sendGuard))

    }

  }

  /// Each way this summary is weaker than a baseline's.
  fileprivate func weakenings(comparedTo baseline: SafetySummary) -> [Finding] {

    var findings: [Finding] = []

    for command in baseline.neverSent.subtracting(neverSent).sorted(by: { ($0.command1, $0.command2) < ($1.command1, $1.command2) }) {

      let name: String = command.command1 == CommandSetSafety.setOperatingFlagsCommand1 ? "Set Operating Flags" : "cmd1 \(hex(command.command1))"

      findings.append(Finding(kind: .sendsNeverSentBytes, detail: "\(name) \(hex(command.command2))"))

    }

    for command2 in unlockedFloor.subtracting(baseline.unlockedFloor).sorted() {

      findings.append(Finding(kind: .unlocksProtectedCommand, detail: "Set Operating Flags \(hex(command2))"))

    }

    func describe(_ key: BitsKey) -> (GuardWeakening.Kind, String) {

      switch key {
      case let .query(query):
        return (.flagBits, "Get Operating Flags \(hex(query.rawValue))")
      case let .parameter(command, fixed, location):
        let bytes: String = fixed.map { (byte: FixedUserDataByte) -> String in " D\(byte.position) \(hex(byte.value))" }.joined()
        return (.parameterBits, "cmd1 \(hex(command.command1)) cmd2 \(hex(command.command2))\(bytes) \(location)")
      case let .value(position):
        return (.valueBits, "D\(position)")
      }

    }

    for (key, kept) in baseline.keptBits {

      let missing: UInt8 = kept & ~(keptBits[key] ?? 0)

      if missing != 0 {

        let (kind, place): (GuardWeakening.Kind, String) = describe(key)

        findings.append(Finding(kind: kind, detail: "\(place) kept bits \(hex(missing))"))

      }

    }

    for (key, neverSet) in baseline.neverSetBits {

      let missing: UInt8 = neverSet & ~((neverSetBits[key] ?? 0) | (keptBits[key] ?? 0))

      if missing != 0 {

        let (kind, place): (GuardWeakening.Kind, String) = describe(key)

        findings.append(Finding(kind: kind, detail: "\(place) never-set bits \(hex(missing))"))

      }

    }

    for (position, query) in baseline.flagsQueries.sorted(by: { $0.key < $1.key }) where flagsQueries[position] != query {

      findings.append(Finding(kind: .flagsQuery, detail: "D\(position) Get Operating Flags \(hex(query.rawValue))"))

    }

    for selector in baseline.guardedSelectors.subtracting(guardedSelectors).sorted() {

      findings.append(Finding(kind: .writeSelector, detail: "extended Set selector \(hex(selector))"))

    }

    for key in unguardedCommands.intersection(baseline.guardedCommands) {

      switch key {
      case let .standard(command1, command2):
        findings.append(Finding(kind: .commandGuard, detail: "cmd1 \(hex(command1))" + (command2.map { " cmd2 \(hex($0))" } ?? "")))
      case let .extended(command, fixed):
        let bytes: String = fixed.map { (byte: FixedUserDataByte) -> String in " D\(byte.position) \(hex(byte.value))" }.joined()
        findings.append(Finding(kind: .commandGuard, detail: "extended cmd1 \(hex(command.command1)) cmd2 \(hex(command.command2))\(bytes)"))
      }

    }

    return findings.sorted { ($0.kind.rawValue, $0.detail) < ($1.kind.rawValue, $1.detail) }

  }

}
