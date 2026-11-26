import Foundation
import InsteonCore
import InsteonService
import Testing

@testable import InsteonAppUI

/// The first screen's acceptance tests, through the calls the screen makes and without a view.
@MainActor
struct DevicesScreenTests {

  private let lamp = ServiceDevice(
    address: InsteonAddress("1A.2B.3C")!, productName: "Lamp Module", canTurnOnAndOff: true, canDim: true, value: 0, lastAnsweredAt: nil)
  private let sensor = ServiceDevice(
    address: InsteonAddress("4D.5E.6F")!, productName: nil, canTurnOnAndOff: false, canDim: false, value: nil, lastAnsweredAt: nil)

  @Test func loadingListsTheDevicesTheHomeKnows() async {
    let home = ScriptedHome(devices: [lamp, sensor])
    let screen = DevicesScreen(home: home)

    await screen.load()

    #expect(screen.state == .loaded)
    #expect(screen.rows.map(\.title) == ["Lamp Module", "Unidentified device"])
    #expect(screen.rows.map(\.subtitle) == ["1A.2B.3C", "4D.5E.6F"])
    #expect(screen.rows.map(\.canSwitch) == [true, false])
  }

  @Test func aDeviceThatReportedALevelShowsItOnOrOff() async {
    var on = lamp
    on = ServiceDevice(address: lamp.address, productName: lamp.productName, canTurnOnAndOff: true, canDim: true, value: 128, lastAnsweredAt: nil)
    let screen = DevicesScreen(home: ScriptedHome(devices: [on, lamp]))

    await screen.load()

    #expect(screen.rows[0].level == .percent(50))
    #expect(screen.rows[1].level == .off)
  }

  @Test func aDeviceThatNeverReportedALevelShowsNone() async {
    let never = ServiceDevice(address: lamp.address, productName: nil, canTurnOnAndOff: true, canDim: false, value: nil, lastAnsweredAt: nil)
    let screen = DevicesScreen(home: ScriptedHome(devices: [never]))

    await screen.load()

    #expect(screen.rows[0].level == .unknown)
  }

  @Test func turningADeviceOnSendsOneOnCommandAndShowsItOn() async {
    let home = ScriptedHome(devices: [lamp])
    let screen = DevicesScreen(home: home)
    await screen.load()

    await screen.turn(screen.rows[0], on: true)

    #expect(home.commands == [ServiceCommand(address: lamp.address, action: .on)])
    #expect(screen.rows[0].level == .percent(100))
    #expect(screen.notice == nil)
  }

  @Test func turningADeviceOffSendsOneOffCommandAndShowsItOff() async {
    let home = ScriptedHome(devices: [lamp])
    let screen = DevicesScreen(home: home)
    await screen.load()

    await screen.turn(screen.rows[0], on: false)

    #expect(home.commands == [ServiceCommand(address: lamp.address, action: .off)])
    #expect(screen.rows[0].level == .off)
  }

  @Test func aRefusedCommandLeavesTheRowAndSaysWhy() async {
    let home = ScriptedHome(devices: [lamp], refusal: ServiceControlError.modemUnavailable(.connecting))
    let screen = DevicesScreen(home: home)
    await screen.load()

    await screen.turn(screen.rows[0], on: true)

    #expect(screen.rows[0].level == .off)
    #expect(screen.notice != nil)
  }

  @Test func aDeviceThatCannotSwitchSendsNothing() async {
    let home = ScriptedHome(devices: [sensor])
    let screen = DevicesScreen(home: home)
    await screen.load()

    await screen.turn(screen.rows[0], on: true)

    #expect(home.commands.isEmpty)
  }

  @Test func aHomeThatCannotBeReadShowsTheFailureAndNoRows() async {
    let screen = DevicesScreen(home: ScriptedHome(devices: [], listFailure: ServiceControlError.busy))

    await screen.load()

    guard case .failed(let message) = screen.state else { Issue.record("expected a failure"); return }
    #expect(!message.isEmpty)
    #expect(screen.rows.isEmpty)
  }
}
