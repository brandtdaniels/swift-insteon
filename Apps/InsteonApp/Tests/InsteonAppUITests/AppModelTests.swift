import InsteonClient
import InsteonCore
import InsteonDemo
import InsteonService
import Testing

@testable import InsteonAppUI

/// Which network the app runs on: the demo network, or a paired service.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppModelTests {

  @Test func theAppAsksWhichNetworkBeforeAnyIsChosen() {
    let model = AppModel(arguments: [])

    #expect(model.devices == nil)
  }

  @Test func choosingTheDemoListsTheDemoDevices() async throws {
    let model = AppModel(arguments: [])

    model.choose(.demo)
    let screen = try #require(model.devices)
    await screen.load()

    #expect(screen.state == .loaded)
    #expect(screen.rows.contains { $0.id == DemoNetwork.lamp })
  }

  @Test func turningTheDemoLampOnChangesItsShownLevel() async throws {
    let model = AppModel(arguments: [])
    model.choose(.demo)
    let screen = try #require(model.devices)
    await screen.load()
    let lamp = try #require(screen.rows.first { $0.id == DemoNetwork.lamp })

    await screen.turn(lamp, on: true)

    #expect(screen.notice == nil)
    #expect(screen.rows.first { $0.id == DemoNetwork.lamp }?.level == .percent(100))
  }

  @Test func theDemoLaunchArgumentChoosesTheDemoWithNoQuestion() throws {
    let model = AppModel(arguments: ["InsteonApp", "--demo"])

    #expect(model.devices != nil)
  }

  @Test func anotherArgumentChoosesNothing() {
    let model = AppModel(arguments: ["InsteonApp", "--other"])

    #expect(model.devices == nil)
  }

  @Test func aPairedChoiceAsksTheConnectionNotTheDemo() async throws {
    let model = AppModel(arguments: [])

    model.choose(.paired(ClientConnection(paths: [])))
    let screen = try #require(model.devices)
    await screen.load()

    #expect(screen.rows.isEmpty)
    #expect(screen.failure != nil)
  }

  @Test func choosingAgainReplacesTheScreen() async throws {
    let model = AppModel(arguments: ["--demo"])
    let demo = try #require(model.devices)
    await demo.load()
    #expect(!demo.rows.isEmpty)

    model.choose(.paired(ClientConnection(paths: [])))
    let paired = try #require(model.devices)
    await paired.load()

    #expect(paired.rows.isEmpty)
  }

  @Test func eachChoiceGivesTheScreenANewIdentity() {
    let model = AppModel(arguments: [])
    let none = model.identity

    model.choose(.demo)
    let first = model.identity
    model.choose(.paired(ClientConnection(paths: [])))

    #expect(first != none)
    #expect(model.identity != first)
  }

  @Test func theScenesScreenIsMissingUntilANetworkIsChosen() {
    #expect(AppModel(arguments: []).scenes == nil)
  }

  @Test func choosingTheDemoGivesAScenesScreenThatReadsAndRunsTheDemoScenes() async throws {
    let model = AppModel(arguments: [])
    model.choose(.demo)
    let screen = try #require(model.scenes)

    await screen.load()
    #expect(screen.isEmpty, "the demo's databases are read on request")
    await screen.refresh()
    let scene = try #require(screen.rows.first)
    await screen.run(scene, .on)

    #expect(screen.isWhole)
    #expect(screen.rows.allSatisfy { $0.canRun })
    #expect(screen.outcome?.kind == .complete)
  }

  @Test func aPairedChoiceGivesAScenesScreenOverTheConnection() async throws {
    let model = AppModel(arguments: [])

    model.choose(.paired(ClientConnection(paths: [])))
    let screen = try #require(model.scenes)
    await screen.load()

    #expect(screen.rows.isEmpty)
    #expect(screen.failure == "The service couldn't be reached.")
  }

  @Test func theDemoLaunchArgumentGivesBothScreens() {
    let model = AppModel(arguments: ["InsteonApp", "--demo"])

    #expect(model.devices != nil && model.scenes != nil)
  }
}
