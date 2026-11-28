import InsteonClient
import InsteonCore
import InsteonLinking
import InsteonProtocol
import InsteonService
import Testing

private let modem = InsteonAddress(0x11, 0x22, 0x33)
private let keypad = InsteonAddress(0x4D, 0x5E, 0x6F)
private let unlistedSensor = InsteonAddress(0x0A, 0x0B, 0x0C)

/// A service that answers its scenes from values a test gives it and records what it was asked.
private actor FakeSceneService: SceneProviding {
  var listing: SceneListing
  var meanings: [InsteonAddress: LinkDataMeaning]
  var receipt: SceneReceipt
  var failure: ServiceControlError?
  private(set) var calls: [String] = []
  private(set) var commands: [SceneCommand] = []

  init(listing: SceneListing, meanings: [InsteonAddress: LinkDataMeaning] = [:], receipt: SceneReceipt = SceneReceipt(scene: 3, action: .on, acknowledged: [], unacknowledged: [], isComplete: true, responderCount: 0), failure: ServiceControlError? = nil) {
    self.listing = listing
    self.meanings = meanings
    self.receipt = receipt
    self.failure = failure
  }

  func scenes() async -> SceneListing {
    calls.append("scenes")
    return listing
  }

  func refreshScenes() async throws -> SceneListing {
    calls.append("refreshScenes")
    if let failure { throw failure }
    return listing
  }

  func runScene(_ command: SceneCommand) async throws -> SceneReceipt {
    calls.append("runScene")
    commands.append(command)
    if let failure { throw failure }
    return receipt
  }

  func planSceneMembership(_ change: SceneMembershipChange) async throws -> SceneMembershipPlanReceipt {
    calls.append("planSceneMembership")
    throw failure ?? ServiceControlError.unknownScene
  }

  func applySceneMembership(scene: UInt8, planId: String, consent: DatabaseLinkConsent) async throws -> SceneMembershipApplication {
    calls.append("applySceneMembership")
    throw failure ?? ServiceControlError.unknownPlan
  }

  func meaning(ofMemberData data: [UInt8], of device: InsteonAddress, group: UInt8) async -> LinkDataMeaning? { meanings[device] }
}

private let onLevel = LinkDataMeaning(bytes: [
  LinkDataField(position: 1, name: "onLevel", label: "On-level", value: 0xFF, valueName: "On", verification: "observed"),
  LinkDataField(position: 3, name: "group", value: 0x01, isPerGroup: true, verification: "inferred")
])

private let halfLink = AllLinkGroupReading.HalfLink(endpoint: .device(lampAddress), record: AllLinkRecord(flags: [.inUse], group: 4, address: modem, data1: 0xFF, data2: 0x1F, data3: 0x01))

private let listing = SceneListing(
  scenes: [
    SceneListing.Scene(number: 3, controller: .modem, members: [SceneListing.Member(address: lampAddress, data: [0xFF, 0x1F, 0x01]), SceneListing.Member(address: keypad, data: [0, 0, 0])], halfLinks: [halfLink]),
    SceneListing.Scene(number: 2, controller: .device(keypad), members: [])
  ],
  looseHalfLinks: [halfLink], unreadable: [unlistedSensor], unreadableReasons: [unlistedSensor: .noAnswer], unlisted: [keypad], isModemUnread: true)

@Suite("A service's scenes give the client's shapes", .timeLimit(.minutes(1)))
struct ServiceScenesTests {

  @Test func theListingMapsSceneBySceneWithTheMembersBytesNamedByTheCatalog() async throws {
    let scenes = ServiceScenes(FakeSceneService(listing: listing, meanings: [lampAddress: onLevel]))

    let list = try await scenes.scenes()

    #expect(list.scenes.map(\.number) == [3, 2])
    #expect(list.scenes.map(\.source) == [.modem, .device(keypad)])
    #expect(list.scenes.map(\.isWritable) == [true, false])
    let lamp = try #require(list.scenes.first?.members.first)
    #expect(lamp.address == lampAddress)
    #expect(lamp.data == [0xFF, 0x1F, 0x01])
    #expect(lamp.isDescribed)
    #expect(lamp.bytes == [
      SceneList.Byte(position: 1, name: "onLevel", label: "On-level", value: 0xFF, valueName: "On", isPerGroup: false, verification: .observed),
      SceneList.Byte(position: 3, name: "group", label: nil, value: 0x01, valueName: nil, isPerGroup: true, verification: .inferred)
    ])
  }

  @Test func aMemberTheCatalogDoesNotDescribeHasNoBytesAndIsListedOnce() async throws {
    let scenes = ServiceScenes(FakeSceneService(listing: listing, meanings: [lampAddress: onLevel]))

    let list = try await scenes.scenes()

    let member = try #require(list.scenes.first?.members.last)
    #expect(member.address == keypad && !member.isDescribed && member.bytes.isEmpty && member.data == [0, 0, 0])
    #expect(list.undescribedMembers == [keypad])
  }

  @Test func whatWasNotReadAndHalfLinksComeThroughSoTheListIsNotWhole() async throws {
    let list = try await ServiceScenes(FakeSceneService(listing: listing)).scenes()

    #expect(!list.isWhole)
    #expect(list.isModemUnread)
    #expect(list.unreadable == [SceneList.UnreadableDevice(address: unlistedSensor, reason: .noAnswer)])
    #expect(list.unlisted == [keypad])
    let expected = SceneList.HalfLink(endpoint: .device(lampAddress), group: 4, address: modem, role: .responder, data: [0xFF, 0x1F, 0x01])
    #expect(list.looseHalfLinks == [expected])
    #expect(list.scenes.first?.halfLinks == [expected])
  }

  @Test func everyReasonTheCoreHasMapsToTheSameNamedReason() async throws {
    let pairs: [(BackupUnreadableReason, SceneList.UnreadableReason)] = [
      (.noAnswer, .noAnswer), (.rejectedModem, .rejectedModem), (.damagedRecords, .damagedRecords), (.notCached, .notCached),
      (.unavailableFromSource, .unavailableFromSource), (.modemStoppedEchoing, .modemStoppedEchoing),
      (.hubStoppedAnswering, .hubStoppedAnswering), (.failed, .failed), (.incomplete, .incomplete)
    ]
    for (core, client) in pairs {
      let one = SceneListing(scenes: [], unreadable: [lampAddress], unreadableReasons: [lampAddress: core])

      let list = try await ServiceScenes(FakeSceneService(listing: one)).scenes()

      #expect(list.unreadable.map(\.reason) == [client], "\(core)")
    }
  }

  @Test func aWholeEmptyListingIsAWholeEmptyList() async throws {
    let list = try await ServiceScenes(FakeSceneService(listing: SceneListing(scenes: []))).scenes()

    #expect(list.scenes.isEmpty && list.isWhole && !list.isModemUnread)
  }

  @Test func aRefreshReadsTheHardwareAndMapsTheSameWay() async throws {
    let service = FakeSceneService(listing: listing)

    let list = try await ServiceScenes(service).refreshScenes()

    #expect(await service.calls == ["refreshScenes"])
    #expect(list.scenes.map(\.number) == [3, 2])
  }

  @Test func aRunSendsTheNumberAndActionOnceAndMapsTheReceipt() async throws {
    let receipt = SceneReceipt(scene: 3, action: .off, acknowledged: [lampAddress], unacknowledged: [keypad], isComplete: false, responderCount: 2, persistence: .failed)
    let service = FakeSceneService(listing: listing, receipt: receipt)

    let answer = try await ServiceScenes(service).runScene(3, action: .off, idempotencyKey: "ignored")

    #expect(await service.commands == [SceneCommand(number: 3, action: .off)])
    #expect(answer == SceneRunReceipt(scene: 3, action: .off, acknowledged: [lampAddress], unacknowledged: [keypad], isComplete: false, responderCount: 2, persistence: .failed))
  }

  @Test func aNumberThatIsNotAGroupIsInvalidSceneAndNothingIsSent() async throws {
    let service = FakeSceneService(listing: listing)

    for number in [0, -1, 255, 256, 1000] {
      await #expect(throws: ConnectionError.invalidScene, "\(number)") { _ = try await ServiceScenes(service).runScene(number, action: .on, idempotencyKey: nil) }
    }
    #expect(await service.calls.isEmpty)
  }

  @Test func theServicesRefusalsPassThroughAsTheirOwnErrors() async throws {
    let service = FakeSceneService(listing: listing, failure: .busy)

    await #expect(throws: ServiceControlError.busy) { _ = try await ServiceScenes(service).refreshScenes() }
    await #expect(throws: ServiceControlError.busy) { _ = try await ServiceScenes(service).runScene(3, action: .on, idempotencyKey: nil) }
  }

  @Test func aConnectionIsAlsoAScenesSourceSoAScreenTakesEither() {
    func accepts(_: some SceneManaging) {}

    accepts(ClientConnection(paths: []))
    accepts(ServiceScenes(FakeSceneService(listing: listing)))
  }
}
