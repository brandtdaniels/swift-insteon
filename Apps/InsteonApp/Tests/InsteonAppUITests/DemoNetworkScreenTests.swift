import InsteonDemo
import InsteonService
import Testing

@testable import InsteonAppUI

/// The devices screen over the demo network, which the app runs on when no Hub is at hand.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DemoNetworkScreenTests {

  @Test func theDemoNetworkListsItsDevices() async {
    let screen = DevicesScreen(network: DemoNetwork.make())

    await screen.load()

    #expect(screen.state == .loaded)
    #expect(screen.rows.count >= 3)
    #expect(screen.rows.allSatisfy { $0.canSwitch })
  }

  @Test func turningADemoDeviceOnShowsItOnWhenTheScreenReadsAgain() async {
    let screen = DevicesScreen(network: DemoNetwork.make())
    await screen.load()
    let row = screen.rows[0]
    #expect(row.level == .unknown || row.level == .off)

    await screen.turn(row, on: true)
    #expect(screen.notice == nil)
    await screen.load()

    #expect(screen.rows[0].level == .percent(100))
  }

  @Test func turningADemoDeviceOffReadsBackOff() async {
    let screen = DevicesScreen(network: DemoNetwork.make())
    await screen.load()
    await screen.turn(screen.rows[0], on: true)

    await screen.turn(screen.rows[0], on: false)
    await screen.load()

    #expect(screen.rows[0].level == .off)
  }
}
