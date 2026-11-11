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

    /// Bits of a byte written on a route, an extended Set's selector and D position or an
    /// extended command's bytes and D position, that the baseline keeps or never sets for a
    /// value read at some D position or for a flags parameter, which the catalog guards less on
    /// that route.
    case writtenBits

    /// Bits of an extended settings value's byte that a write of the value keeps or never sets
    /// in the baseline, which a write of a value of the same name or position guards less.
    case valueBits

    /// A value whose byte the baseline marks as an operating flags byte, which the catalog
    /// doesn't mark with the same query.
    case flagsQuery

    /// A command the baseline guards, whose bytes the catalog sends with no guard.
    case commandGuard

    /// A command whose effect the baseline ranks stricter, or names differently among
    /// configuration, link and actuation, which the catalog gives a weaker or different one,
    /// or a command the baseline describes as other than read-only, which the catalog doesn't
    /// describe by its bytes. An effect that's missing or unknown reads as destructive.
    case effect

    /// A command the baseline doesn't mark idempotent, which the catalog does.
    case idempotent

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
  /// For every category and subcategory a profile of either catalog has an identity for, and
  /// for every firmware version `0x00` through `0xFF` and none where a profile narrows by
  /// firmware, each catalog's command set for that device is found as an app finds it,
  /// whatever its id, and summarized with the rules InsteonCore applies when it sends
  /// (`CommandSetSafety`). This catalog is at least as strict for the device when:
  /// - it never sends every byte the baseline never sends, and unlocks no protected Set
  ///   Operating Flags cmd2 the baseline keeps refused;
  /// - it keeps or never sets every operating flag bit, per Get Operating Flags query, the
  ///   baseline does;
  /// - on every route a byte is written on, an extended Set's selector and D position or an
  ///   extended command's bytes, fixed bytes and D position, it guards every bit the baseline
  ///   guards there at least as strictly, for the same place the byte is read from, or for no
  ///   place; these routes and their guards are what the send path checks every extended
  ///   message against (`CommandSetSafety.guardViolation(by:userData:in:current:)`);
  /// - each value guards, as a write of it finds its bits, every bit the baseline's value of
  ///   the same name or the same position guards, with the same flags query;
  /// - it sends no bytes of a command the baseline guards from an unguarded command;
  /// - for every command with the bytes of one of the baseline's, found as the send path finds
  ///   it by cmd1, its fixed cmd2 and its fixed bytes, whatever its name, the strictest of its
  ///   effects ranks at least as strict and is the same effect unless it is destructive or
  ///   read-only, and it is idempotent only where the baseline's is. A missing or unknown effect
  ///   reads as destructive and a missing mark as not idempotent, as the send path reads them.
  ///   A command the baseline describes as other than read-only, which this catalog leaves
  ///   without an entry of those bytes, is weaker too: a message no entry describes needs less
  ///   consent than a destructive one;
  /// - a modem's serial commands are compared the same way, by command number and fixed payload
  ///   bytes, and a serial command the baseline never sends stays never sent.
  ///
  /// A device either catalog gives no command set, or doesn't know, is compared as one with
  /// none, which only the byte floor guards. The send path refuses an extended Set as given to
  /// a device with no command set, and one whose selector a command set doesn't list, so a
  /// command set refuses at least that much: a catalog may give a device a command set, as
  /// long as it unlocks no protected cmd2 for it. Profile data, such as linking changes,
  /// keep-awake messages and relay state holding, isn't compared.
  ///
  /// - Parameter baseline: The catalog whose guards are the least this one gives, such as
  ///   ``DeviceCatalog/bundled()``.
  /// - Returns: Each way it's weaker, once per device, kind and detail, ordered by category
  ///   and subcategory; none when it's at least as strict.
  public func guardWeakenings(comparedTo baseline: DeviceCatalog) -> [GuardWeakening] {

    let firmwareVersions: [FirmwareVersion?] = [nil] + (UInt8.min...UInt8.max).map { (version: UInt8) -> FirmwareVersion? in FirmwareVersion(rawValue: version) }
    // A device only this catalog knows is compared with a device the baseline doesn't know,
    // which only the byte floor guards.
    var seen: Set<[UInt8]> = []
    let identities = (baseline.indexedIdentities + indexedIdentities).filter { (identity) -> Bool in

      seen.insert([identity.category.rawValue, identity.subcategory.rawValue]).inserted

    }.sorted { (left, right) -> Bool in

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

  /// Where a guarded operating flag bit is: its flags byte, by the Get Operating Flags query
  /// that reads it, which Set Operating Flags writes.
  enum BitsKey: Hashable {

    case query(OperatingFlagsRequest)

  }

  /// The kept and never-set bits of the bytes written on each route, by where the byte is
  /// read, or `nil` for a flags parameter nothing reads.
  struct Masks: Hashable {

    var kept: UInt8 = 0

    var neverSet: UInt8 = 0

  }

  var routeMasks: [CommandSetSafety.ByteRoute: [Int?: Masks]] = [:]

  /// A command by the bytes it sends: a standard message's cmd1 and its fixed cmd2, if any,
  /// or an extended message's cmd1, cmd2 and fixed bytes.
  enum CommandKey: Hashable {

    case standard(UInt8, UInt8?)

    case extended(Command, [FixedUserDataByte])

    case serial(UInt8, [FixedPayloadByte])

  }

  /// The bytes never sent, the byte floor's included.
  var neverSent: Set<Command> = []

  /// The protected Set Operating Flags cmd2s the command set unlocks.
  var unlockedFloor: Set<UInt8> = []

  /// The kept bits, by where they are.
  var keptBits: [BitsKey: UInt8] = [:]

  /// The never-set bits, by where they are.
  var neverSetBits: [BitsKey: UInt8] = [:]

  /// What a write of one extended settings value guards, as the write finds it.
  struct ValueGuard: Hashable {

    let name: SettingName

    let position: Int

    /// The Get Operating Flags query the value's byte is the reply of, if any.
    let flagsQuery: OperatingFlagsRequest?

    let kept: UInt8

    let neverSet: UInt8

  }

  /// Each extended settings value's guards, in the command set's order.
  var values: [ValueGuard] = []

  /// The commands guarded, and those not, by their bytes.
  var guardedCommands: Set<CommandKey> = []

  var unguardedCommands: Set<CommandKey> = []

  /// What a command does and whether it's idempotent, as the send path reads them, by the
  /// command's bytes: the strictest effect of the commands with the same bytes, and idempotent
  /// only if every one of them is.
  struct Effect: Hashable {

    let effect: CommandEffect

    let isIdempotent: Bool

    /// The effect of several commands with the same bytes.
    func combined(with other: Effect) -> Effect {

      let combined: CommandEffect

      if effect.strictness != other.effect.strictness {

        combined = effect.strictness > other.effect.strictness ? effect : other.effect

      } else {

        combined = effect == other.effect ? effect : .destructive

      }

      return Effect(effect: combined, isIdempotent: isIdempotent && other.isIdempotent)

    }

  }

  var effects: [CommandKey: Effect] = [:]

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

    // The guards of every byte written, by route, as the send path decides them.
    for (route, guards) in CommandSetSafety.routeGuards(in: commands) {

      var byPosition: [Int?: Masks] = [:]

      for guardOnRoute in guards {

        for bit in guardOnRoute.bits {

          switch bit.rule {
          case .keep:
            byPosition[guardOnRoute.readPosition, default: Masks()].kept |= bit.mask
          case .neverSet:
            byPosition[guardOnRoute.readPosition, default: Masks()].neverSet |= bit.mask
          }

        }

      }

      routeMasks[route] = byPosition

    }

    let settings: ExtendedSettings? = commands.extendedSettings

    for value in settings?.values ?? [] {

      // The bits a write of the value guards, as the write itself finds them.
      let bits: [CommandSetSafety.GuardedBit] = CommandSetSafety.guardedBits(in: value, of: commands)
      let kept: UInt8 = bits.filter { (bit: CommandSetSafety.GuardedBit) -> Bool in bit.rule == .keep }.reduce(0) { $0 | $1.mask }
      let neverSet: UInt8 = bits.filter { (bit: CommandSetSafety.GuardedBit) -> Bool in bit.rule == .neverSet }.reduce(0) { $0 | $1.mask }

      values.append(ValueGuard(name: value.name, position: value.position, flagsQuery: value.flagsQuery, kept: kept, neverSet: neverSet))

    }

    func add(_ key: CommandKey, isGuarded: Bool) {

      if isGuarded {

        guardedCommands.insert(key)

      } else {

        unguardedCommands.insert(key)

      }

    }

    func addEffect(_ key: CommandKey, effect: CommandEffect?, isIdempotent: Bool?) {

      let read: CommandEffect = effect.flatMap { (effect: CommandEffect) -> CommandEffect? in effect.strictness == .destructive ? nil : effect } ?? .destructive
      let entry = Effect(effect: read, isIdempotent: isIdempotent == true)

      effects[key] = effects[key].map { (known: Effect) -> Effect in known.combined(with: entry) } ?? entry

    }

    for command in commands.flagCommands {

      let key: CommandKey = .standard(command.command.command.command1, command.command.command.command2)

      add(key, isGuarded: CommandSetSafety.isNeverSent(command.sendGuard))
      addEffect(key, effect: command.effect, isIdempotent: command.isIdempotent)

    }

    for command in commands.standardCommands {

      var command2: UInt8?

      if case let .fixed(fixed) = command.command2 {

        command2 = fixed

      }

      add(.standard(command.command1, command2), isGuarded: CommandSetSafety.isNeverSent(command.sendGuard))
      addEffect(.standard(command.command1, command2), effect: command.effect, isIdempotent: command.isIdempotent)

    }

    for command in commands.extendedCommands {

      add(.extended(command.command, CommandSetSafety.keyBytes(of: command)), isGuarded: CommandSetSafety.isNeverSent(command.sendGuard))
      addEffect(.extended(command.command, CommandSetSafety.keyBytes(of: command)), effect: command.effect, isIdempotent: command.isIdempotent)

    }

    for command in commands.serialCommands {

      let key: CommandKey = .serial(command.number, command.fixedBytes)

      add(key, isGuarded: CommandSetSafety.isNeverSent(command.sendGuard))
      addEffect(key, effect: command.effect, isIdempotent: command.isIdempotent)

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
      }

    }

    // A route's guards, by where its byte is read, are kept at least as strictly: a guard
    // read elsewhere, or by no report, isn't the same guard.
    for (route, byPosition) in baseline.routeMasks {

      let place: String

      switch route {
      case let .extendedSet(selector, position):
        place = "extended Set selector \(hex(selector)) D\(position)"
      case let .extendedCommand(command, fixed, position):
        let bytes: String = fixed.map { (byte: FixedUserDataByte) -> String in " D\(byte.position) \(hex(byte.value))" }.joined()
        place = "cmd1 \(hex(command.command1)) cmd2 \(hex(command.command2))\(bytes) D\(position)"
      }

      let new: [Int?: Masks] = routeMasks[route] ?? [:]
      let newKeptAnywhere: UInt8 = new.values.reduce(0) { $0 | $1.kept }
      let newGuardedAnywhere: UInt8 = new.values.reduce(0) { $0 | $1.kept | $1.neverSet }

      // A never-set bit is refused when a write sets it, wherever its byte is read, so it's
      // compared on the route as a whole.
      let oldNeverSet: UInt8 = byPosition.values.reduce(0) { $0 | $1.neverSet }
      let missingNeverSet: UInt8 = oldNeverSet & ~newGuardedAnywhere

      if missingNeverSet != 0 {

        findings.append(Finding(kind: .writtenBits, detail: "\(place) never-set bits \(hex(missingNeverSet))"))

      }

      // A kept bit is compared with the device's report where its byte is read: the same place,
      // or none, which refuses every write. One read nowhere is kept as strictly anywhere.
      for (readPosition, masks) in byPosition where masks.kept != 0 {

        let keptThere: UInt8 = readPosition.map { (position: Int) -> UInt8 in (new[position]?.kept ?? 0) | (new[Int?.none]?.kept ?? 0) } ?? newKeptAnywhere
        let missingKept: UInt8 = masks.kept & ~keptThere
        let read: String = readPosition.map { (position: Int) -> String in "read at D\(position)" } ?? "read nowhere"

        if missingKept != 0 {

          findings.append(Finding(kind: .writtenBits, detail: "\(place) \(read) kept bits \(hex(missingKept))"))

        }

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

    // Each value is compared with the baseline's value of its name and every baseline value
    // at its position, so a value at the same byte can't stand in for one that lost a guard.
    for value in values {

      for old in baseline.values where old.name == value.name || old.position == value.position {

        let place: String = "\(value.name) D\(value.position)"

        if let query = old.flagsQuery, value.flagsQuery != query {

          findings.append(Finding(kind: .flagsQuery, detail: "\(place) Get Operating Flags \(hex(query.rawValue))"))

        }

        let missingKept: UInt8 = old.kept & ~value.kept
        let missingNeverSet: UInt8 = old.neverSet & ~(value.neverSet | value.kept)

        if missingKept != 0 {

          findings.append(Finding(kind: .valueBits, detail: "\(place) kept bits \(hex(missingKept))"))

        }

        if missingNeverSet != 0 {

          findings.append(Finding(kind: .valueBits, detail: "\(place) never-set bits \(hex(missingNeverSet))"))

        }

      }

    }

    func describe(_ key: CommandKey) -> String {

      switch key {
      case let .standard(command1, command2):
        return "cmd1 \(hex(command1))" + (command2.map { " cmd2 \(hex($0))" } ?? "")
      case let .extended(command, fixed):
        let bytes: String = fixed.map { (byte: FixedUserDataByte) -> String in " D\(byte.position) \(hex(byte.value))" }.joined()

        return "extended cmd1 \(hex(command.command1)) cmd2 \(hex(command.command2))\(bytes)"
      case let .serial(number, fixed):
        let bytes: String = fixed.map { (byte: FixedPayloadByte) -> String in " payload \(byte.position) \(hex(byte.value))" }.joined()

        return "serial \(hex(number))\(bytes)"
      }

    }

    for key in unguardedCommands.intersection(baseline.guardedCommands) {

      findings.append(Finding(kind: .commandGuard, detail: describe(key)))

    }

    // A command's effect is compared by its bytes: the new effect has to rank at least as
    // strict, and among the effects of one rank, configuration, link and actuation, be the
    // same. A command the baseline describes as other than read-only, which the catalog no
    // longer describes by those bytes, is undescribed, which an app may send with less consent
    // than a destructive one.
    for (key, old) in baseline.effects {

      guard let new = effects[key] else {

        if old.effect.strictness != .readOnly {

          findings.append(Finding(kind: .effect, detail: "\(describe(key)) \(old.effect) to undescribed"))

        }

        continue

      }

      let isWeaker: Bool = new.effect.strictness < old.effect.strictness || (new.effect.strictness == .change && old.effect.strictness == .change && new.effect != old.effect)

      if isWeaker {

        findings.append(Finding(kind: .effect, detail: "\(describe(key)) \(old.effect) to \(new.effect)"))

      }

      if new.isIdempotent && !old.isIdempotent {

        findings.append(Finding(kind: .idempotent, detail: describe(key)))

      }

    }

    return findings.sorted { ($0.kind.rawValue, $0.detail) < ($1.kind.rawValue, $1.detail) }

  }

}
