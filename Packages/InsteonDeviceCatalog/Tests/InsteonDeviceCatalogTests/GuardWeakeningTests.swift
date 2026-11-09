import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonNetworking
import InsteonProtocol

/// A catalog an app loads in place of a baseline may make a device's guards stricter but never
/// weaker, compared device by device through the command set each catalog gives it, with
/// made-up devices and command sets whose names no real product has.
struct GuardWeakeningTests {

  /// The made-up switch's identity, which every catalog here gives a profile.
  static let category = DeviceCategory(rawValue: 0x01)

  static let subcategory = DeviceSubcategory(rawValue: 0x7A)

  /// A command set with a guard of every kind: a lockout never set, a radio mute kept, a
  /// flags parameter with both, a never-sent flag command and extended command, and a value
  /// holding the operating flags byte that an extended Set writes.
  static func guarded(
    id: CommandSetID = "exampleGuarded",
    lockout: FlagGuard? = .neverSet,
    radioMute: FlagGuard? = .keep,
    radioMuteOn: UInt8 = 0x0C,
    lockoutBit: FlagGuard? = .neverSet,
    lockOnName: SettingName = "lockOn",
    lockOn: CommandGuard? = .never,
    writeLock: CommandGuard? = .never,
    writeFlagsName: SettingName = "writeFlags",
    flagsQuery: OperatingFlagsRequest? = .operatingFlags,
    flagsByteWrite: SettingName? = nil,
    extraFlags: [OperatingFlag] = [],
    extraFlagCommands: [OperatingFlagCommand] = [],
    extraExtendedCommands: [DeviceExtendedCommand] = []
  ) -> CommandSet {

    CommandSet(
      id: id,
      name: "Example guarded",
      summary: "Guards of every kind.",
      operatingFlags: [
        OperatingFlag(name: "lockout", summary: "Locks out linking.", query: .operatingFlags, bit: 0x01, on: 0x00, off: 0x01, writeGuard: lockout),
        OperatingFlag(name: "radioMute", summary: "Mutes the radio.", query: .operatingFlags, bit: 0x40, on: radioMuteOn, off: 0x0D, writeGuard: radioMute),
        OperatingFlag(name: "pressTone", summary: "Beeps.", query: .operatingFlags, bit: 0x02, on: 0x0A, off: 0x0B)
      ] + extraFlags,
      flagCommands: [
        OperatingFlagCommand(name: lockOnName, summary: "Locks out linking.", command2: 0x00, sendGuard: lockOn),
        OperatingFlagCommand(name: "lockOff", summary: "Allows linking.", command2: 0x01)
      ] + extraFlagCommands,
      extendedSettings: ExtendedSettings(
        isPerButton: false,
        values: [
          SettingValue(name: "configuration", summary: "The flags byte.", position: 7, label: "Configuration", flagsQuery: flagsQuery),
          SettingValue(name: "flagsByte", summary: "The flags parameter's byte.", position: 8, label: "Flags byte", write: flagsByteWrite ?? writeFlagsName)
        ],
        writes: [SettingWrite(name: "configuration", summary: "Writes the flags byte.", selector: 0x05, isPerButton: false, bytes: [SettingWrite.Byte(position: 3, value: "configuration")])]
      ),
      extendedCommands: [
        DeviceExtendedCommand(
          name: writeFlagsName,
          summary: "Writes the flags.",
          command: Command(command1: 0x2E, command2: 0x00),
          fixedBytes: [FixedUserDataByte(position: 2, value: 0x07)],
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
      ] + extraExtendedCommands
    )

  }

  /// The made-up switch's command set with every guard taken away.
  static func stripped(id: CommandSetID) -> CommandSet {

    guarded(id: id, lockout: nil, radioMute: nil, lockoutBit: nil, lockOn: nil, writeLock: nil, flagsQuery: nil)

  }

  /// A profile of the made-up switch, for its identity or a range of firmware.
  static func profile(_ entries: [CommandSetID], model: String = "9701", firmware: ClosedRange<FirmwareVersion>? = nil) -> DeviceProfile {

    DeviceProfile(
      model: ProductModel(rawValue: model),
      name: "Example Guarded Switch",
      identities: [DeviceIdentity(category: category, subcategory: subcategory, firmware: firmware)],
      commandSets: entries.map { (id: CommandSetID) -> CommandSetEntry in CommandSetEntry(commandSet: id, category: category, subcategory: subcategory) }
    )

  }

  /// A catalog of profiles and command sets.
  static func catalog(_ profiles: [DeviceProfile], _ commandSets: [CommandSet]) -> DeviceCatalog {

    DeviceCatalog(profiles: profiles, commandSets: commandSets)

  }

  /// The made-up switch, fully guarded.
  static let baseline: DeviceCatalog = catalog([profile(["exampleGuarded"])], [guarded()])

  /// The weakenings of a catalog compared with the baseline.
  static func weakenings(_ catalog: DeviceCatalog) -> [GuardWeakening] {

    catalog.guardWeakenings(comparedTo: baseline)

  }

  /// The weakenings of the baseline's profile with another command set in place of its own.
  static func weakenings(_ commands: CommandSet) -> [GuardWeakening] {

    weakenings(catalog([profile([commands.id])], [commands]))

  }

  /// The kinds of the weakenings found.
  static func kinds(_ weakenings: [GuardWeakening]) -> Set<GuardWeakening.Kind> {

    Set(weakenings.map(\.kind))

  }

  /// Every kind a fully stripped command set shows.
  static let everyKind: Set<GuardWeakening.Kind> = [
    .sendsNeverSentBytes, .unlocksProtectedCommand, .flagBits, .parameterBits, .valueBits, .flagsQuery, .writeSelector, .commandGuard, .rawWrite
  ]

  // MARK: - Refused

  @Test func refusesGuardsTakenAwayInPlace() {

    let weakenings: [GuardWeakening] = Self.weakenings(Self.stripped(id: "exampleGuarded"))

    #expect(Self.kinds(weakenings) == Self.everyKind)
    #expect(weakenings.allSatisfy { (weakening: GuardWeakening) -> Bool in weakening.category == Self.category && weakening.subcategory == Self.subcategory })
    #expect(weakenings.contains(GuardWeakening(category: Self.category, subcategory: Self.subcategory, firmwareVersion: nil, kind: .unlocksProtectedCommand, detail: "Set Operating Flags 0x0C")))

  }

  @Test func refusesAStrippedCommandSetUnderANewID() {

    // The command set is renamed, and the device points at the new name.
    #expect(Self.kinds(Self.weakenings(Self.stripped(id: "exampleGuardedV2"))) == Self.everyKind)

  }

  @Test func refusesAStrippedCopyTheDeviceIsPointedAt() {

    // The guarded command set is kept, but the device points at a stripped copy.
    let added: DeviceCatalog = Self.catalog([Self.profile(["exampleStripped"])], [Self.guarded(), Self.stripped(id: "exampleStripped")])

    #expect(Self.kinds(Self.weakenings(added)) == Self.everyKind)

  }

  @Test func refusesAStrippedCopyListedFirstForTheDevice() {

    let ordered: DeviceCatalog = Self.catalog([Self.profile(["exampleStripped", "exampleGuarded"])], [Self.guarded(), Self.stripped(id: "exampleStripped")])

    #expect(Self.kinds(Self.weakenings(ordered)) == Self.everyKind)

  }

  @Test func refusesAProtectedByteAGuardedFlagLeavesForAnUnguardedCommand() {

    // Radio mute keeps its name and guard, but turns on with 0x7C, and an unguarded flag
    // command takes 0x0C.
    let moved: CommandSet = Self.guarded(radioMuteOn: 0x7C, extraFlagCommands: [OperatingFlagCommand(name: "quiet", summary: "Quiets.", command2: 0x0C)])
    let weakenings: [GuardWeakening] = Self.weakenings(moved)

    #expect(weakenings.map(\.detail).contains("Set Operating Flags 0x0C"))
    #expect(Self.kinds(weakenings) == [.sendsNeverSentBytes, .unlocksProtectedCommand])

  }

  @Test func refusesAProtectedByteAnotherFlagTurnsOff() {

    // Radio mute turns on with 0x7C, and an unguarded flag turns off with 0x0C.
    let widget = OperatingFlag(name: "widget", summary: "A widget.", query: .operatingFlags, bit: 0x04, on: 0x7B, off: 0x0C)
    let weakenings: [GuardWeakening] = Self.weakenings(Self.guarded(radioMuteOn: 0x7C, extraFlags: [widget]))

    #expect(weakenings.contains { (weakening: GuardWeakening) -> Bool in weakening.kind == .unlocksProtectedCommand && weakening.detail == "Set Operating Flags 0x0C" })

  }

  @Test func refusesAStrippedCommandSetForOneFirmwareVersion() throws {

    // A profile for firmware 0x45 alone, which the catalog prefers for that version.
    let firmware = FirmwareVersion(rawValue: 0x45)
    let specific: DeviceCatalog = Self.catalog(
      [Self.profile(["exampleGuarded"]), Self.profile(["exampleStripped"], model: "9702", firmware: firmware...firmware)],
      [Self.guarded(), Self.stripped(id: "exampleStripped")]
    )
    let weakenings: [GuardWeakening] = Self.weakenings(specific)

    #expect(Self.kinds(weakenings) == Self.everyKind)
    #expect(Set(weakenings.map(\.firmwareVersion)) == [firmware])

  }

  @Test func refusesADeviceTheCatalogDrops() {

    let dropped: DeviceCatalog = Self.catalog([], [Self.guarded()])

    #expect(!Self.weakenings(dropped).isEmpty)

  }

  @Test func refusesEachGuardLostOnItsOwn() {

    // Its on, 0x00, stays never sent, as the guarded lockOn names it too.
    #expect(Self.kinds(Self.weakenings(Self.guarded(lockout: nil))) == [.flagBits, .valueBits])
    #expect(Self.kinds(Self.weakenings(Self.guarded(radioMute: .neverSet))).contains(.flagBits))
    #expect(Self.kinds(Self.weakenings(Self.guarded(lockoutBit: nil))) == [.parameterBits, .valueBits, .rawWrite])
    #expect(Self.kinds(Self.weakenings(Self.guarded(flagsQuery: nil))) == [.flagsQuery, .valueBits, .writeSelector])
    #expect(Self.kinds(Self.weakenings(Self.guarded(flagsQuery: OperatingFlagsRequest(rawValue: 0x05)))).contains(.flagsQuery))

  }

  @Test func refusesAFlagsParameterWithTheSameBytesAndNoGuard() {

    // The command is renamed and its bit loses its guard; bit guards follow the command's
    // bytes and the parameter's place, not its name.
    #expect(Self.kinds(Self.weakenings(Self.guarded(lockoutBit: nil, writeFlagsName: "writeBits"))) == [.parameterBits, .valueBits, .rawWrite])

  }

  @Test func refusesAValueWrittenThroughAnUnguardedCommandWithTheSameBytes() {

    // A second command with the guarded command's bytes, whose bit has no guard, writes the
    // value; bit guards are kept per command bytes and parameter, and per value.
    let twin = DeviceExtendedCommand(
      name: "writeFlagsTwin",
      summary: "Writes the flags.",
      command: Command(command1: 0x2E, command2: 0x00),
      fixedBytes: [FixedUserDataByte(position: 2, value: 0x07)],
      parameters: [MessageField(name: "flags", summary: "The flags.", location: .userData([3]), kind: .flags([FieldBit(mask: 0x01, name: "lockout")]))]
    )

    #expect(Self.kinds(Self.weakenings(Self.guarded(flagsByteWrite: "writeFlagsTwin", extraExtendedCommands: [twin]))) == [.valueBits])
    // With the value still written through the guarded command, the twin changes nothing.
    #expect(Self.weakenings(Self.guarded(extraExtendedCommands: [twin])).isEmpty)

  }

  @Test func refusesThroughCheckGuards() {

    let weaker: DeviceCatalog = Self.catalog([Self.profile(["exampleGuarded"])], [Self.guarded(lockoutBit: nil)])

    #expect(throws: DeviceCatalogError.weakensGuards(weaker.guardWeakenings(comparedTo: Self.baseline))) {

      try weaker.checkGuards(against: Self.baseline)

    }

    #expect(weaker.guardWeakenings(comparedTo: Self.baseline).map(\.description) == [
      "0x01/0x7A parameterBits cmd1 0x2E cmd2 0x00 D2 0x07 userData([3]) never-set bits 0x01",
      "0x01/0x7A rawWrite extended cmd1 0x2E cmd2 0x00 D2 0x07",
      "0x01/0x7A valueBits flagsByte D8 never-set bits 0x01"
    ])

  }

  // MARK: - Refused: a byte written as given

  /// A made-up switch whose flags byte, D7, which holds a kept radio mute bit, is written by
  /// an extended command, `0x4B 0x00`, with the byte in D3.
  static func written(
    id: CommandSetID = "exampleWritten",
    flagsQuery: OperatingFlagsRequest? = .operatingFlags,
    write: SettingName? = "writeConfig",
    hasWriteCommand: Bool = true,
    decoy: Bool = false,
    decoyWrite: SettingName? = nil,
    selectorWrite: Bool = false,
    unguardedFlag: Bool = false
  ) -> CommandSet {

    var values: [SettingValue] = [SettingValue(name: "configuration", summary: "The flags byte.", position: 7, label: "Configuration", write: write, flagsQuery: flagsQuery)]
    var writes: [SettingWrite] = []

    if decoy {

      values.append(SettingValue(name: "decoy", summary: "The same byte.", position: 7, label: "Decoy", write: decoyWrite, flagsQuery: .operatingFlags))

    }

    if selectorWrite {

      writes.append(SettingWrite(
        name: "configuration",
        summary: "Writes the flags byte.",
        selector: 0x05,
        isPerButton: false,
        bytes: [SettingWrite.Byte(position: 3, value: "configuration")] + (decoy ? [SettingWrite.Byte(position: 4, value: "decoy")] : [])
      ))

    }

    var flags: [OperatingFlag] = [OperatingFlag(name: "radioMute", summary: "Mutes the radio.", query: .operatingFlags, bit: 0x40, on: 0x7C, off: 0x7D, writeGuard: .keep)]

    if unguardedFlag {

      flags.append(OperatingFlag(name: "quiet", summary: "Quiets.", query: .operatingFlags, bit: 0x08, on: 0x0C, off: 0x0D))

    }

    return CommandSet(
      id: id,
      name: "Example written",
      summary: "A flags byte an extended command writes.",
      operatingFlags: flags,
      extendedSettings: ExtendedSettings(isPerButton: false, values: values, writes: writes),
      extendedCommands: hasWriteCommand
        ? [DeviceExtendedCommand(name: "writeConfig", summary: "Writes the byte.", command: Command(command1: 0x4B, command2: 0x00), parameters: [MessageField(name: "configuration", summary: "The byte.", location: .userData([3]))])]
        : []
    )

  }

  /// The weakenings of the written switch's command set against its baseline.
  static func writtenWeakenings(_ commands: CommandSet, baseline: CommandSet = written()) -> [GuardWeakening] {

    catalog([profile([commands.id])], [commands]).guardWeakenings(comparedTo: catalog([profile([baseline.id])], [baseline]))

  }

  @Test func refusesAGuardedByteWhoseWriteIsUnlinked() {

    // The value doesn't name the command that writes it, so a raw message with that command's
    // bytes isn't refused.
    #expect(Self.kinds(Self.writtenWeakenings(Self.written(write: nil))).contains(.rawWrite))

  }

  @Test func refusesAGuardedByteWhoseWriteCommandIsGone() {

    #expect(Self.kinds(Self.writtenWeakenings(Self.written(hasWriteCommand: false))).contains(.rawWrite))

  }

  @Test func refusesAValueThatLosesItsGuardBehindADecoyAtItsPosition() {

    // The value loses its flags query, and a decoy at D7 has it.
    let weakenings: [GuardWeakening] = Self.writtenWeakenings(Self.written(flagsQuery: nil, decoy: true, decoyWrite: "writeConfig"))

    #expect(weakenings.contains { (weakening: GuardWeakening) -> Bool in weakening.kind == .valueBits && weakening.detail.hasPrefix("configuration") })

  }

  @Test func refusesAValueThatLosesItsGuardBehindADecoyInTheSameSelectorWrite() {

    let baseline: CommandSet = Self.written(selectorWrite: true)
    let weakenings: [GuardWeakening] = Self.writtenWeakenings(Self.written(flagsQuery: nil, decoy: true, selectorWrite: true), baseline: baseline)

    #expect(weakenings.contains { (weakening: GuardWeakening) -> Bool in weakening.kind == .valueBits && weakening.detail.hasPrefix("configuration") })

  }

  @Test func refusesACommandSetForADeviceTheBaselineGivesNone() {

    // With no command set, an extended Set as given is refused; with one, it's sent unless a
    // write it names holds guarded flags.
    let baseline: DeviceCatalog = Self.catalog([Self.profile([])], [])
    let empty = CommandSet(id: "exampleEmpty", name: "Example empty", summary: "No settings.")
    let given: DeviceCatalog = Self.catalog([Self.profile(["exampleEmpty"])], [empty])

    #expect(Self.kinds(given.guardWeakenings(comparedTo: baseline)) == [.extendedSetRefusal])

  }

  @Test func refusesADeviceOnlyTheCatalogKnowsWhenItUnlocksAProtectedByte() {

    let other = DeviceProfile(
      model: "9798",
      name: "Example Loose",
      identities: [DeviceIdentity(category: 0x01, subcategory: 0x7B)],
      commandSets: [CommandSetEntry(commandSet: "exampleLoose", category: 0x01, subcategory: 0x7B)]
    )
    let weakenings: [GuardWeakening] = Self.catalog([Self.profile(["exampleGuarded"]), other], [Self.guarded(), Self.written(id: "exampleLoose", unguardedFlag: true)])
      .guardWeakenings(comparedTo: Self.baseline)

    #expect(weakenings.contains(GuardWeakening(category: 0x01, subcategory: 0x7B, firmwareVersion: nil, kind: .unlocksProtectedCommand, detail: "Set Operating Flags 0x0C")))
    #expect(weakenings.allSatisfy { (weakening: GuardWeakening) -> Bool in weakening.subcategory == 0x7B })

  }

  // MARK: - Accepted

  @Test func acceptsAnEqualOrStricterCatalog() {

    #expect(Self.weakenings(Self.guarded()).isEmpty)
    #expect(Self.weakenings(Self.guarded(lockout: .keep)).isEmpty)
    #expect(Self.weakenings(Self.guarded(radioMute: FlagGuard(rawValue: "somethingNewer"))).isEmpty)

    var stricter: CommandSet = Self.guarded()

    stricter.operatingFlags[2].writeGuard = .keep

    #expect(Self.weakenings(stricter).isEmpty)

  }

  @Test func acceptsRenamesThatKeepEveryGuard() {

    // The command set, a guarded command and a flags parameter's command are renamed with
    // the same bytes and guards.
    #expect(Self.weakenings(Self.guarded(id: "exampleGuardedV2", lockOnName: "engageLock", writeFlagsName: "writeBits")).isEmpty)

  }

  @Test func acceptsADeviceOnlyTheCatalogHasWithNoCommandSet() {

    // A profile with no command set leaves the device as guarded as one the catalog doesn't
    // know; one with a command set doesn't, as an extended Set as given is then sent.
    let other = DeviceProfile(model: "9799", name: "Example Other", identities: [DeviceIdentity(category: 0x02, subcategory: 0x7A)], commandSets: [])

    #expect(Self.weakenings(Self.catalog([Self.profile(["exampleGuarded"]), other], [Self.guarded()])).isEmpty)

  }

  @Test func acceptsTheBundledCopyAgainstItself() throws {

    let bundled: DeviceCatalog = try DeviceCatalog.bundled()

    #expect(bundled.guardWeakenings(comparedTo: bundled).isEmpty)

  }

  // MARK: - Updating

  @Test(.timeLimit(.minutes(1))) func refusesADownloadThatWeakensTheBaselinesGuards() async throws {

    let json = Data(Self.catalogJSON(lockOnGuard: nil).utf8)
    let files = DeviceCatalogUpdaterTests.files(manifest: try DeviceCatalogUpdaterTests.manifest(sha256: DeviceCatalogUpdaterTests.sha256(of: json)), catalog: json)
    let baseline: DeviceCatalog = try DeviceCatalog(json: Data(Self.catalogJSON(lockOnGuard: .never).utf8))
    let weakenings: [GuardWeakening] = try DeviceCatalog(json: json).guardWeakenings(comparedTo: baseline)

    #expect(!weakenings.isEmpty)

    await #expect(throws: DeviceCatalogUpdateError.weakensGuards(weakenings)) {

      try await DeviceCatalogUpdater(client: files, guardBaseline: baseline).update(replacing: nil, currentVersion: nil)

    }

    // The same download is used with a baseline it doesn't weaken.
    let unguarded: DeviceCatalog = try DeviceCatalog(json: Data(Self.catalogJSON(lockOnGuard: nil).utf8))
    let update = try await DeviceCatalogUpdater(client: files, guardBaseline: unguarded).update(replacing: nil, currentVersion: nil)

    guard case .updated = update else {

      Issue.record("Expected updated, got \(update).")

      return

    }

  }

  /// A catalog in its JSON: a device whose command set has a flag command that turns its
  /// lockout on, with the guard given.
  static func catalogJSON(lockOnGuard: CommandGuard?) -> String {

    let guardJSON: String = lockOnGuard.map { (sendGuard: CommandGuard) -> String in #", "guard": "\#(sendGuard.rawValue)""# } ?? ""

    return #"""
      { "devices": [{ "model": "9703", "name": "Example JSON Switch", "identities": [{ "category": "0x01", "subcategory": "0x7C" }],
          "commandSets": [{ "commandSet": "exampleJSON", "category": "0x01", "subcategory": "0x7C" }], "capabilities": [], "sources": ["A"] }],
        "commandSets": [{ "id": "exampleJSON", "name": "Example", "description": "A flag command.", "sources": ["A"],
          "flagCommands": [{ "name": "lockOn", "description": "Locks out linking.", "command2": "0x00"\#(guardJSON) }] }] }
      """#

  }

}
