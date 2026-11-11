import Testing
import InsteonDeviceCatalog
import InsteonProtocol

/// A catalog an app loads in place of a baseline may not weaken a modem's serial commands: not
/// make a command's effect weaker, mark it idempotent, drop its guard, or drop a command that
/// does something, with made-up modems and command sets.
struct SerialCommandWeakeningTests {

  /// A command set of serial commands: two that differ by a fixed byte, a read-only one, and one
  /// that is never sent.
  static func modem(
    id: CommandSetID = "exampleModem",
    erase: (CommandEffect?, Bool?) = (.destructive, true),
    store: (CommandEffect?, Bool?) = (.configuration, true),
    askIdentity: (CommandEffect?, Bool?) = (.readOnly, true),
    includesStore: Bool = true,
    includesAskIdentity: Bool = true,
    eraseGuard: CommandGuard? = .never,
    extra: [DeviceSerialCommand] = []
  ) -> CommandSet {

    var serial: [DeviceSerialCommand] = [
      DeviceSerialCommand(
        name: "erase",
        summary: "Erases a pairing.",
        number: 0x64,
        fixedBytes: [FixedPayloadByte(position: 1, value: 0xFF)],
        sendGuard: eraseGuard,
        effect: erase.0,
        isIdempotent: erase.1
      )
    ]

    if includesStore {

      serial.append(DeviceSerialCommand(name: "store", summary: "Stores a setting.", number: 0x68, effect: store.0, isIdempotent: store.1))

    }

    if includesAskIdentity {

      serial.append(DeviceSerialCommand(name: "askIdentity", summary: "Asks who it is.", number: 0x60, effect: askIdentity.0, isIdempotent: askIdentity.1))

    }

    return CommandSet(id: id, name: "Example modem", summary: "Serial commands.", serialCommands: serial + extra)

  }

  static func profile(_ entries: [CommandSetID]) -> DeviceProfile {

    GuardWeakeningTests.profile(entries, model: "9702")

  }

  static let baseline: DeviceCatalog = DeviceCatalog(profiles: [profile(["exampleModem"])], commandSets: [modem()])

  static func weakenings(_ commands: CommandSet?) -> [GuardWeakening] {

    DeviceCatalog(profiles: [profile(commands.map { [$0.id] } ?? [])], commandSets: commands.map { [$0] } ?? []).guardWeakenings(comparedTo: baseline)

  }

  @Test func acceptsACatalogThatChangesNothing() {

    #expect(Self.weakenings(Self.modem()).isEmpty)

  }

  @Test func refusesASerialEffectMadeWeaker() {

    for weaker in [CommandEffect.configuration, .link, .actuation, .readOnly] {

      let weakenings: [GuardWeakening] = Self.weakenings(Self.modem(erase: (weaker, true)))

      #expect(weakenings.filter { $0.kind == .effect }.map(\.detail) == ["serial 0x64 payload 1 0xFF destructive to \(weaker)"])

    }

  }

  @Test func refusesASerialEffectChangedAmongConfigurationLinkAndActuation() {

    #expect(Self.weakenings(Self.modem(store: (.link, true))).map(\.kind) == [.effect])
    #expect(Self.weakenings(Self.modem(store: (.actuation, true))).map(\.kind) == [.effect])

  }

  @Test func readsAMissingOrUnknownSerialEffectAsDestructive() {

    // Missing and unknown effects read as destructive, so they are as strict as the baseline's
    // destructive and weaker than nothing.
    #expect(Self.weakenings(Self.modem(erase: (nil, true))).isEmpty)
    #expect(Self.weakenings(Self.modem(erase: (CommandEffect(rawValue: "sideEffect"), true))).isEmpty)
    #expect(Self.weakenings(Self.modem(store: (nil, true))).isEmpty)

  }

  @Test func refusesASerialCommandMarkedIdempotentThatTheBaselineDoesNot() {

    let loose: DeviceCatalog = DeviceCatalog(profiles: [Self.profile(["exampleModem"])], commandSets: [Self.modem(erase: (.destructive, false))])
    let weakenings: [GuardWeakening] = DeviceCatalog(profiles: [Self.profile(["exampleModem"])], commandSets: [Self.modem()]).guardWeakenings(comparedTo: loose)

    #expect(weakenings.map(\.kind) == [.idempotent])
    #expect(Self.weakenings(Self.modem(erase: (.destructive, nil))).isEmpty)

  }

  @Test func refusesACatalogThatDropsASerialCommandThatDoesSomething() {

    let weakenings: [GuardWeakening] = Self.weakenings(Self.modem(includesStore: false))

    #expect(weakenings.map(\.kind) == [.effect])
    #expect(weakenings.map(\.detail) == ["serial 0x68 configuration to undescribed"])

    let noModem: [GuardWeakening] = Self.weakenings(nil)

    #expect(noModem.map(\.kind).contains(.effect))

  }

  @Test func acceptsACatalogThatDropsAReadOnlySerialCommand() {

    #expect(Self.weakenings(Self.modem(includesAskIdentity: false)).isEmpty)

  }

  @Test func refusesACatalogThatDropsASerialCommandsGuard() {

    let weakenings: [GuardWeakening] = Self.weakenings(Self.modem(eraseGuard: nil))

    #expect(weakenings.map(\.kind) == [.commandGuard])
    #expect(weakenings.map(\.detail) == ["serial 0x64 payload 1 0xFF"])

  }

  @Test func acceptsASerialCommandRenamedAndMovedToAnotherCommandSet() {

    let renamed: DeviceSerialCommand = DeviceSerialCommand(name: "tune", summary: "Stores.", number: 0x68, effect: .configuration, isIdempotent: true)
    var moved: CommandSet = Self.modem(id: "exampleModemV2", includesStore: false, extra: [renamed])

    moved.serialCommands.reverse()

    #expect(Self.weakenings(moved).isEmpty)

  }

  @Test func acceptsAStricterSerialEffect() {

    #expect(Self.weakenings(Self.modem(store: (.destructive, true), askIdentity: (.configuration, true))).isEmpty)

  }

}
