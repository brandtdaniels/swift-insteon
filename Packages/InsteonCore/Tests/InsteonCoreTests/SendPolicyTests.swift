import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

/// What a message needs before it's sent, decided from its effect, a refusal the guards or the
/// byte floor already made, and what the operation grants, with made-up command sets.
struct SendPolicyTests {

  static let commandSet = #"""
    {
      "id": "examplePolicy",
      "name": "Example policy",
      "description": "A made-up command set whose entries carry every kind of effect.",
      "operatingFlags": [],
      "standardCommands": [
        { "name": "readLevel", "description": "Reads the level.", "command1": "0x19", "command2": "0x00", "effect": "readOnly", "idempotent": true },
        { "name": "setTrim", "description": "Sets the trim.", "command1": "0x30", "command2": "0x00", "effect": "configuration", "idempotent": true },
        { "name": "pulse", "description": "Pulses the load.", "command1": "0x31", "command2": "0x00", "effect": "actuation", "idempotent": true },
        { "name": "wipe", "description": "Wipes the records.", "command1": "0x32", "command2": "0x00", "effect": "destructive", "idempotent": true },
        { "name": "unmarked", "description": "Marks nothing.", "command1": "0x33", "command2": "0x00" },
        { "name": "sideways", "description": "Does something newer.", "command1": "0x34", "command2": "0x00", "effect": "sideEffect", "idempotent": true },
        { "name": "pairedTrim", "description": "Trims a pairing.", "command1": "0x35", "command2": "0x00", "effect": "configuration", "idempotent": true },
        { "name": "pairedWipe", "description": "Wipes a pairing.", "command1": "0x35", "command2": "0x00", "effect": "destructive", "idempotent": true }
      ],
      "sources": ["A"]
    }
    """#

  static func commands() throws -> CommandSet {

    let json: String = #"{ "devices": [], "commandSets": [\#(commandSet)] }"#

    return try #require(try DeviceCatalog(json: Data(json.utf8)).commandSet(id: "examplePolicy"))

  }

  /// The effect the command set gives a standard message with cmd2 `0x00`, or `nil` where it
  /// describes none.
  static func effect(ofCommand1 command1: UInt8, in commands: CommandSet?) -> CommandEffect? {

    guard case let .described(effect, _) = CommandSetSafety.effect(of: Command(command1: command1, command2: 0x00), userData: nil, in: commands) else {

      return nil

    }

    return effect

  }

  static let everything = SendConsent(effects: [.readOnly, .configuration, .link, .actuation, .destructive], allowsUndescribed: true)

  static func consent(_ effects: CommandEffect...) -> SendConsent {

    SendConsent(effects: Set(effects))

  }

  // MARK: - Rows 5 to 7

  @Test func transmitsAReadOnlyMessageWithAnyConsent() {

    #expect(SendPolicy.decision(effect: .readOnly, consent: SendConsent()) == .transmit)
    #expect(SendPolicy.decision(effect: .readOnly, consent: Self.consent(.actuation)) == .transmit)
    #expect(SendPolicy.decision(effect: .readOnly, consent: Self.everything) == .transmit)

  }

  @Test func asksForConsentToConfigureWhenOnlyActuationIsGranted() {

    #expect(SendPolicy.decision(effect: .configuration, consent: Self.consent(.actuation)) == .needsConsent(.configuration))

  }

  @Test func transmitsAnActuationTheOperationGrants() {

    #expect(SendPolicy.decision(effect: .actuation, consent: Self.consent(.actuation)) == .transmit)

  }

  @Test func asksForConsentToDestroyWhenEveryOtherEffectIsGranted() {

    let consent: SendConsent = Self.consent(.configuration, .link, .actuation)

    #expect(SendPolicy.decision(effect: .destructive, consent: consent) == .needsConsent(.destructive))

  }

  @Test func transmitsADestructiveMessageTheOperationGrants() {

    #expect(SendPolicy.decision(effect: .destructive, consent: Self.consent(.destructive)) == .transmit)

  }

  // MARK: - Rows 1 and 2

  @Test func refusesWhatAGuardRefusesWhateverTheConsent() {

    let refusal: SendRefusal = .neverSentToDevice(product: "the example relay")

    #expect(SendPolicy.decision(effect: .destructive, refusal: refusal, consent: Self.everything) == .refuse(refusal))

  }

  @Test func refusesPokeWhateverTheConsent() {

    let refusal: SendRefusal = .protected(.poke)

    #expect(SendPolicy.decision(effect: nil, refusal: refusal, consent: Self.everything) == .refuse(refusal))

  }

  // MARK: - Row 3

  @Test func readsAMissingEffectAsDestructive() throws {

    let commands: CommandSet = try Self.commands()
    let effect: CommandEffect? = Self.effect(ofCommand1: 0x33, in: commands)
    let consent: SendConsent = Self.consent(.configuration, .link, .actuation)

    #expect(SendPolicy.decision(effect: effect, consent: consent) == .needsConsent(.destructive))

  }

  @Test func readsAnEffectThePackageDoesNotKnowAsDestructive() throws {

    let commands: CommandSet = try Self.commands()
    let effect: CommandEffect? = Self.effect(ofCommand1: 0x34, in: commands)
    let consent: SendConsent = Self.consent(.configuration, .link, .actuation, CommandEffect(rawValue: "sideEffect"))

    #expect(SendPolicy.decision(effect: effect, consent: consent) == .needsConsent(.destructive))
    #expect(SendPolicy.decision(effect: CommandEffect(rawValue: "sideEffect"), consent: consent) == .needsConsent(.destructive))
    #expect(SendPolicy.decision(effect: CommandEffect(rawValue: "sideEffect"), consent: Self.consent(.destructive)) == .transmit)

  }

  // MARK: - Row 4

  @Test func asksForConsentToSendWhatNoEntryDescribes() throws {

    let commands: CommandSet = try Self.commands()
    let effect: CommandEffect? = Self.effect(ofCommand1: 0x77, in: commands)
    let granted: SendConsent = SendConsent(effects: [.configuration, .link, .actuation, .destructive])

    #expect(effect == nil)
    #expect(SendPolicy.decision(effect: effect, consent: granted) == .needsConsent(nil))
    #expect(SendPolicy.decision(effect: effect, consent: SendConsent(allowsUndescribed: true)) == .transmit)

  }

  @Test func asksForConsentToSendToADeviceWithNoCommandSet() {

    #expect(Self.effect(ofCommand1: 0x19, in: nil) == nil)
    #expect(SendPolicy.decision(effect: nil, consent: Self.consent(.actuation)) == .needsConsent(nil))

  }

  @Test func stillRefusesWhatNoEntryDescribesWhenTheOperationAllowsIt() {

    let refusal: SendRefusal = .protected(.setOperatingFlags0x0C)

    #expect(SendPolicy.decision(effect: nil, refusal: refusal, consent: Self.everything) == .refuse(refusal))

  }

  // MARK: - Several entries

  @Test func readsTwoEntriesForTheSameBytesAsTheStricterOfThem() throws {

    let commands: CommandSet = try Self.commands()
    let effect: CommandEffect? = Self.effect(ofCommand1: 0x35, in: commands)

    #expect(effect == .destructive)
    #expect(SendPolicy.decision(effect: effect, consent: Self.consent(.configuration)) == .needsConsent(.destructive))

  }

  @Test func readsTwoDifferentEffectsOfEqualRankAsDestructive() {

    let consent: SendConsent = Self.consent(.configuration, .link, .actuation)

    #expect(SendPolicy.decision(effect: .link, declaredEffect: .actuation, consent: consent) == .needsConsent(.destructive))

  }

  // MARK: - Declared effects

  @Test func usesTheCatalogsStricterEffectOverAFlowsDeclaredOne() throws {

    let commands: CommandSet = try Self.commands()
    let described: CommandEffect? = Self.effect(ofCommand1: 0x31, in: commands)

    #expect(described == .actuation)
    #expect(SendPolicy.decision(effect: described, declaredEffect: .readOnly, consent: Self.consent(.configuration)) == .needsConsent(.actuation))

  }

  @Test func usesAFlowsStricterDeclaredEffectOverTheCatalogs() {

    #expect(SendPolicy.decision(effect: .readOnly, declaredEffect: .actuation, consent: SendConsent()) == .needsConsent(.actuation))

  }

  @Test func describesWhatOnlyAFlowDeclares() {

    #expect(SendPolicy.decision(effect: nil, declaredEffect: .readOnly, consent: SendConsent()) == .transmit)
    #expect(SendPolicy.decision(effect: nil, declaredEffect: .link, consent: SendConsent()) == .needsConsent(.link))

  }

}
