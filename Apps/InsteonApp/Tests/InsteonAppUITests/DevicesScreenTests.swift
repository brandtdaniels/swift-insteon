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

  @Test func loadingListsTheDevicesTheNetworkKnows() async {
    let network = ScriptedNetwork(devices: [lamp, sensor])
    let screen = DevicesScreen(network: network)

    await screen.load()

    #expect(screen.state == .loaded)
    #expect(screen.rows.map(\.title) == ["Lamp Module", "Unidentified device"])
    #expect(screen.rows.map(\.subtitle) == ["1A.2B.3C", "4D.5E.6F"])
    #expect(screen.rows.map(\.canSwitch) == [true, false])
  }

  @Test func aLoadDuringACommandDoesNotMoveTheCommandsResultToAnotherDevice() async {
    let other = ServiceDevice(address: InsteonAddress("7A.8B.9C")!, productName: "Other", canTurnOnAndOff: true, canDim: false, value: 0, lastAnsweredAt: nil)
    let network = ScriptedNetwork(devices: [lamp, other])
    let screen = DevicesScreen(network: network)
    await screen.load()
    let lampRow = screen.rows[0]
    await network.holdCommands()

    async let turned: Void = screen.turn(lampRow, on: true)
    await network.waitForHeldCommand()
    await network.setDevices([other, lamp])
    await screen.load()
    await network.release()
    await turned

    #expect(screen.rows.map(\.title) == ["Other", "Lamp Module"])
    #expect(screen.rows.map(\.level) == [.off, .percent(100)])
  }

  @Test func aLoadThatDropsTheDeviceDuringACommandDoesNotCrash() async {
    let network = ScriptedNetwork(devices: [lamp])
    let screen = DevicesScreen(network: network)
    await screen.load()
    let lampRow = screen.rows[0]
    await network.holdCommands()

    async let turned: Void = screen.turn(lampRow, on: true)
    await network.waitForHeldCommand()
    await network.setDevices([])
    await screen.load()
    await network.release()
    await turned

    #expect(screen.rows.isEmpty)
  }

  @Test func anAcknowledgmentWithoutAStatusShowsWhatTheNetworkListsNotAGuess() async {
    let network = ScriptedNetwork(devices: [lamp])
    await network.leaveDevicesAt(0x80)
    let screen = DevicesScreen(network: network)
    await screen.load()

    await screen.turn(screen.rows[0], on: true)

    #expect(screen.rows[0].level == .percent(50))
  }

  @Test func anAcknowledgmentWithAStatusShowsTheStatus() async {
    let network = ScriptedNetwork(devices: [lamp])
    await network.setReply(.acknowledgedWithStatus(DeviceStatus(group: 1, value: 0x40, allLinkDatabaseDelta: 0, reading: .percent(25), isOn: true)))
    await network.leaveDevicesAt(0xFF)
    let screen = DevicesScreen(network: network)
    await screen.load()

    await screen.turn(screen.rows[0], on: true)

    #expect(screen.rows[0].level == .percent(25))
  }

  @Test func aReceiptThatIsNotAnAcknowledgmentShowsWhatTheNetworkListsNotAGuess() async {
    let network = ScriptedNetwork(devices: [lamp])
    await network.setReply(.read)
    await network.leaveDevicesAt(0x80)
    let screen = DevicesScreen(network: network)
    await screen.load()

    await screen.turn(screen.rows[0], on: true)

    #expect(screen.rows[0].level == .percent(50))
  }

  @Test func aDeviceTheNetworkCannotListAfterACommandShowsNoLevelAndSaysSo() async {
    let network = ScriptedNetwork(devices: [lamp])
    let screen = DevicesScreen(network: network)
    await screen.load()
    await network.setListFailure(ServiceControlError.busy)

    await screen.turn(screen.rows[0], on: true)

    #expect(screen.rows[0].level == .unknown)
    #expect(screen.notice != nil)
  }

  @Test func aCancelledLoadLeavesTheRowsAndTheStateAlone() async {
    let network = ScriptedNetwork(devices: [lamp])
    let screen = DevicesScreen(network: network)
    await screen.load()
    await network.setListFailure(CancellationError())

    await screen.load()

    #expect(screen.rows.count == 1)
    #expect(screen.state == .loaded)
  }

  @Test func aCancelledFirstLoadLeavesTheScreenWhereItWas() async {
    let network = ScriptedNetwork(devices: [lamp], listFailure: CancellationError())
    let screen = DevicesScreen(network: network)

    await screen.load()

    #expect(screen.state == .idle)
  }

  @Test func aDeviceThatReportedALevelShowsItOnOrOff() async {
    let on = ServiceDevice(address: lamp.address, productName: lamp.productName, canTurnOnAndOff: true, canDim: true, value: 128, lastAnsweredAt: nil)
    let screen = DevicesScreen(network: ScriptedNetwork(devices: [on, lamp]))

    await screen.load()

    #expect(screen.rows[0].level == .percent(50))
    #expect(screen.rows[1].level == .off)
  }

  @Test func aDeviceThatNeverReportedALevelShowsNone() async {
    let never = ServiceDevice(address: lamp.address, productName: nil, canTurnOnAndOff: true, canDim: false, value: nil, lastAnsweredAt: nil)
    let screen = DevicesScreen(network: ScriptedNetwork(devices: [never]))

    await screen.load()

    #expect(screen.rows[0].level == .unknown)
  }

  @Test func turningADeviceOnSendsOneOnCommandAndShowsItOn() async {
    let network = ScriptedNetwork(devices: [lamp])
    let screen = DevicesScreen(network: network)
    await screen.load()

    await screen.turn(screen.rows[0], on: true)

    #expect(await network.commands == [ServiceCommand(address: lamp.address, action: .on)])
    #expect(screen.rows[0].level == .percent(100))
    #expect(screen.notice == nil)
  }

  @Test func turningADeviceOffSendsOneOffCommandAndShowsItOff() async {
    let network = ScriptedNetwork(devices: [lamp])
    let screen = DevicesScreen(network: network)
    await screen.load()

    await screen.turn(screen.rows[0], on: false)

    #expect(await network.commands == [ServiceCommand(address: lamp.address, action: .off)])
    #expect(screen.rows[0].level == .off)
  }

  @Test func aRefusedCommandLeavesTheRowAndSaysWhy() async {
    let network = ScriptedNetwork(devices: [lamp], refusal: ServiceControlError.modemUnavailable(.connecting))
    let screen = DevicesScreen(network: network)
    await screen.load()

    await screen.turn(screen.rows[0], on: true)

    #expect(screen.rows[0].level == .off)
    #expect(screen.notice != nil)
  }

  @Test func aDeviceThatCannotSwitchSendsNothing() async {
    let network = ScriptedNetwork(devices: [sensor])
    let screen = DevicesScreen(network: network)
    await screen.load()

    await screen.turn(screen.rows[0], on: true)

    #expect(await network.commands.isEmpty)
  }

  @Test func aNetworkThatCannotBeReadShowsTheFailureAndNoRows() async {
    let screen = DevicesScreen(network: ScriptedNetwork(devices: [], listFailure: ServiceControlError.busy))

    await screen.load()

    guard case .failed(let message) = screen.state else { Issue.record("expected a failure"); return }
    #expect(!message.isEmpty)
    #expect(screen.rows.isEmpty)
  }
}
