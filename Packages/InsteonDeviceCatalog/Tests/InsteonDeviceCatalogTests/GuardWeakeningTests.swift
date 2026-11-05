import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonNetworking
import InsteonProtocol

/// A catalog an app loads in place of a baseline may add guards but never weaken one, compared
/// command set by command set, with made-up command sets whose names no real product has.
struct GuardWeakeningTests {

  /// A command set with a guard of every kind: a lockout never set, a radio mute kept, a
  /// flags parameter with both, a never-sent flag command and extended command, and a value
  /// holding the operating flags byte.
  static func guarded(
    id: CommandSetID = "exampleGuarded",
    lockout: FlagGuard? = .neverSet,
    radioMute: FlagGuard? = .keep,
    lockoutBit: FlagGuard? = .neverSet,
    lockOn: CommandGuard? = .never,
    writeLock: CommandGuard? = .never,
    flagsQuery: OperatingFlagsRequest? = .operatingFlags,
    extraFlags: [OperatingFlag] = [],
    extraFlagCommands: [OperatingFlagCommand] = []
  ) -> CommandSet {

    CommandSet(
      id: id,
      name: "Example guarded",
      summary: "Guards of every kind.",
      operatingFlags: [
        OperatingFlag(name: "lockout", summary: "Locks out linking.", query: .operatingFlags, bit: 0x01, on: 0x00, off: 0x01, writeGuard: lockout),
        OperatingFlag(name: "radioMute", summary: "Mutes the radio.", query: .operatingFlags, bit: 0x40, on: 0x0C, off: 0x0D, writeGuard: radioMute),
        OperatingFlag(name: "pressTone", summary: "Beeps.", query: .operatingFlags, bit: 0x02, on: 0x0A, off: 0x0B)
      ] + extraFlags,
      flagCommands: [
        OperatingFlagCommand(name: "lockOn", summary: "Locks out linking.", command2: 0x00, sendGuard: lockOn),
        OperatingFlagCommand(name: "lockOff", summary: "Allows linking.", command2: 0x01)
      ] + extraFlagCommands,
      extendedSettings: ExtendedSettings(
        isPerButton: false,
        values: [SettingValue(name: "configuration", summary: "The flags byte.", position: 7, label: "Configuration", flagsQuery: flagsQuery)],
        writes: []
      ),
      extendedCommands: [
        DeviceExtendedCommand(
          name: "writeFlags",
          summary: "Writes the flags.",
          command: Command(command1: 0x2E, command2: 0x00),
          parameters: [
            MessageField(
              name: "flags",
              summary: "The flags.",
              location: .userData([3]),
              kind: .flags([FieldBit(mask: 0x01, name: "lockout", writeGuard: lockoutBit), FieldBit(mask: 0x02, name: "pressTone")])
            )
          ]
        ),
        DeviceExtendedCommand(name: "writeLock", summary: "Locks by an extended message.", command: Command(command1: 0x20, command2: 0x00), sendGuard: writeLock)
      ]
    )

  }

  static func catalog(_ commandSets: CommandSet...) -> DeviceCatalog {

    DeviceCatalog(profiles: [], commandSets: commandSets)

  }

  static let baseline: DeviceCatalog = catalog(guarded())

  static func weakenings(_ commands: CommandSet) -> [GuardWeakening] {

    catalog(commands).guardWeakenings(comparedTo: baseline)

  }

  static func weakening(_ kind: GuardWeakening.Kind, _ name: SettingName) -> GuardWeakening {

    GuardWeakening(commandSet: "exampleGuarded", kind: kind, name: name)

  }

  // MARK: - Refused

  @Test func findsAFlagThatLosesOrWeakensItsGuard() {

    #expect(Self.weakenings(Self.guarded(lockout: nil)) == [Self.weakening(.flag, "lockout")])
    #expect(Self.weakenings(Self.guarded(radioMute: .neverSet)) == [Self.weakening(.flag, "radioMute")])
    #expect(Self.weakenings(Self.guarded(radioMute: nil)) == [Self.weakening(.flag, "radioMute")])

  }

  @Test func findsAGuardedFlagThatsGoneOrRenamed() {

    var commands: CommandSet = Self.guarded()

    commands.operatingFlags.removeAll { (flag: OperatingFlag) -> Bool in flag.name == "radioMute" }

    #expect(Self.weakenings(commands) == [Self.weakening(.flag, "radioMute")])

    // The same bit under another name, with no guard.
    commands.operatingFlags.append(OperatingFlag(name: "silence", summary: "Silences.", query: .operatingFlags, bit: 0x40, on: 0x0C, off: 0x0D))

    #expect(Self.weakenings(commands) == [Self.weakening(.flag, "radioMute")])

    // Another bit turned on with the kept flag's cmd2.
    let sameBytes = OperatingFlag(name: "other", summary: "Other.", query: .operatingFlags, bit: 0x80, on: 0x0C, off: 0x0E)

    #expect(Self.weakenings(Self.guarded(extraFlags: [sameBytes])) == [Self.weakening(.flag, "radioMute")])

  }

  @Test func findsAFlagsParameterBitThatLosesItsGuard() {

    #expect(Self.weakenings(Self.guarded(lockoutBit: nil)) == [Self.weakening(.flagsBit, "lockout")])

  }

  @Test func findsACommandThatLosesNeverOrIsSentUnderAnotherName() {

    // The flag command and the extended command share Set Operating Flags 0x00, so either
    // losing its guard sends the other's bytes too.
    let both: [GuardWeakening] = [Self.weakening(.command, "lockOn"), Self.weakening(.command, "writeLock")]

    #expect(Self.weakenings(Self.guarded(lockOn: nil)) == both)
    #expect(Self.weakenings(Self.guarded(writeLock: nil)) == both)

    let renamed = OperatingFlagCommand(name: "engage", summary: "Locks out linking.", command2: 0x00)

    #expect(Self.weakenings(Self.guarded(extraFlagCommands: [renamed])).contains(Self.weakening(.command, "lockOn")))

  }

  @Test func findsAValueThatLosesItsFlagsQuery() {

    #expect(Self.weakenings(Self.guarded(flagsQuery: nil)) == [Self.weakening(.flagsQuery, "configuration")])
    #expect(Self.weakenings(Self.guarded(flagsQuery: OperatingFlagsRequest(rawValue: 0x05))) == [Self.weakening(.flagsQuery, "configuration")])

  }

  @Test func refusesItThroughCheckGuardsWithEveryWeakening() {

    let weaker: DeviceCatalog = Self.catalog(Self.guarded(lockout: nil, lockOn: nil))

    let expected: [GuardWeakening] = [Self.weakening(.flag, "lockout"), Self.weakening(.command, "lockOn"), Self.weakening(.command, "writeLock")]

    #expect(throws: DeviceCatalogError.weakensGuards(expected)) {

      try weaker.checkGuards(against: Self.baseline)

    }

    #expect(weaker.guardWeakenings(comparedTo: Self.baseline).map(\.description) == [
      "exampleGuarded flag lockout",
      "exampleGuarded command lockOn",
      "exampleGuarded command writeLock"
    ])

  }

  // MARK: - Accepted

  @Test func acceptsAnEqualOrStricterCatalog() throws {

    #expect(Self.weakenings(Self.guarded()).isEmpty)
    #expect(Self.weakenings(Self.guarded(lockout: .keep)).isEmpty)

    var stricter: CommandSet = Self.guarded()

    stricter.operatingFlags[2].writeGuard = .keep

    #expect(Self.weakenings(stricter).isEmpty)
    #expect(Self.weakenings(Self.guarded(radioMute: FlagGuard(rawValue: "somethingNewer"))).isEmpty)

  }

  @Test func acceptsACommandSetOnlyOneCatalogHas() {

    let onlyNew: DeviceCatalog = Self.catalog(Self.guarded(), Self.guarded(id: "exampleOther", lockout: nil, radioMute: nil, lockoutBit: nil, lockOn: nil, writeLock: nil, flagsQuery: nil))

    #expect(onlyNew.guardWeakenings(comparedTo: Self.baseline).isEmpty)
    #expect(Self.catalog().guardWeakenings(comparedTo: Self.baseline).isEmpty)

  }

  @Test func acceptsTheBundledCopyAgainstItself() throws {

    let bundled: DeviceCatalog = try DeviceCatalog.bundled()

    #expect(bundled.guardWeakenings(comparedTo: bundled).isEmpty)

  }

  // MARK: - Updating

  @Test(.timeLimit(.minutes(1))) func refusesADownloadThatWeakensTheBaselinesGuards() async throws {

    let weaker: CommandSet = Self.guarded(lockOn: nil)
    let json = Data(#"{ "devices": [], "commandSets": [\#(Self.commandSetJSON(lockOnGuard: weaker.flagCommands[0].sendGuard))] }"#.utf8)
    let files = DeviceCatalogUpdaterTests.files(manifest: try DeviceCatalogUpdaterTests.manifest(sha256: DeviceCatalogUpdaterTests.sha256(of: json)), catalog: json)
    let baseline: DeviceCatalog = try DeviceCatalog(json: Data(#"{ "devices": [], "commandSets": [\#(Self.commandSetJSON(lockOnGuard: .never))] }"#.utf8))

    await #expect(throws: DeviceCatalogUpdateError.weakensGuards([GuardWeakening(commandSet: "exampleJSON", kind: .command, name: "lockOn")])) {

      try await DeviceCatalogUpdater(client: files, guardBaseline: baseline).update(replacing: nil, currentVersion: nil)

    }

    // The same download is used with a baseline it doesn't weaken.
    let update = try await DeviceCatalogUpdater(client: files, guardBaseline: Self.catalog()).update(replacing: nil, currentVersion: nil)

    guard case .updated = update else {

      Issue.record("Expected updated, got \(update).")

      return

    }

  }

  /// A command set in the catalog's JSON with a flag command whose guard is given.
  static func commandSetJSON(lockOnGuard: CommandGuard?) -> String {

    let guardJSON: String = lockOnGuard.map { (sendGuard: CommandGuard) -> String in #", "guard": "\#(sendGuard.rawValue)""# } ?? ""

    return #"""
      { "id": "exampleJSON", "name": "Example", "description": "A flag command.", "sources": ["A"],
        "flagCommands": [{ "name": "lockOn", "description": "Locks out linking.", "command2": "0x00"\#(guardJSON) }] }
      """#

  }

}
