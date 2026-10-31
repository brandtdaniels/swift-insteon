import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Control from the bundled catalog's 0.6 data: a zone's state from the bits its `onWhen`
/// names, one output of a load switched on its own, and arm modes.
struct CatalogControlTests {

  let clock: TestClock = TestClock()

  /// The bundled EZFlora's control model.
  func ezFlora() throws -> DeviceControlModel {

    DeviceControlModel.make(try DeviceCatalog.bundled().describe(category: 0x04, subcategory: 0x00, firmwareVersion: nil))

  }

  /// The bundled 0-10V Ballast Dimmer 2475DA2 on a modem whose operating flags are `flags`.
  func makeBallast(flags: UInt8) throws -> (Device, SettingsModem) {

    let address = InsteonAddress(0x6C, 0x7D, 0x01)
    let modem = SettingsModem(device: address, flags: flags, values: [:])
    let network = DeviceNetwork(
      modem: modem,
      catalog: try DeviceCatalog.bundled(),
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [address: ReportedIdentity(category: 0x01, subcategory: 0x25, firmwareVersion: 0x41)])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    )

    return (network.device(address), modem)

  }

  // MARK: - onWhen

  @Test func readsZoneOneOffWhileAnotherZoneRuns() throws {

    let model: DeviceControlModel = try ezFlora()
    let zone1: DeviceControlModel.Group = try #require(model.group(1))
    let zone3: DeviceControlModel.Group = try #require(model.group(3))

    // Bit 7: a valve is on; bits 0 to 2: zone 3, the active valve.
    #expect(Device.reading(of: 0x82, group: zone1, in: model, reply: nil).reading == .onOff(false))
    #expect(!Device.reading(of: 0x82, group: zone1, in: model, reply: nil).isOn)
    #expect(Device.reading(of: 0x82, group: zone3, in: model, reply: nil).reading == .onOff(true))
    // Zone 1 is the active valve but every valve is off.
    #expect(Device.reading(of: 0x00, group: zone1, in: model, reply: nil).reading == .onOff(false))

  }

  @Test func readsZoneOneOnWhenItsBitsMatch() throws {

    let model: DeviceControlModel = try ezFlora()
    let zone1: DeviceControlModel.Group = try #require(model.group(1))

    #expect(Device.reading(of: 0x80, group: zone1, in: model, reply: nil).reading == .onOff(true))
    // Bits the pattern doesn't name don't matter.
    #expect(Device.reading(of: 0xF8, group: zone1, in: model, reply: nil).isOn)

  }

  @Test func readsEveryZoneFromTheSharedValveStatus() throws {

    let model: DeviceControlModel = try ezFlora()

    #expect(model.groups.map(\.number.rawValue) == [1, 2, 3, 4, 5, 6, 7, 8])

    for group in model.groups {

      // Each zone has its own pattern, so the shared reply says which zone is on.
      #expect(model.canRead(group), "zone \(group.number)")

      let active: UInt8 = 0x80 | (group.number.rawValue - 1)

      #expect(Device.reading(of: active, group: group, in: model, reply: nil).isOn, "zone \(group.number)")

      for other in model.groups where other.number != group.number {

        #expect(!Device.reading(of: active, group: other, in: model, reply: nil).isOn, "zone \(other.number) while \(group.number) runs")

      }

    }

    // None of them is the device's level.
    #expect(model.groups.allSatisfy { (group: DeviceControlModel.Group) -> Bool in !model.reportsDeviceLevel(group) })

  }

  // MARK: - Outputs

  @Test(.timeLimit(.minutes(1))) func switchesOneRelayOfTheBallastDimmerInRelayMode() async throws {

    // Relay mode's bit, 0x80 of the Get Operating Flags 0x05 reply, is set; the modem
    // reports the same byte for every query.
    let (ballast, modem): (Device, SettingsModem) = try makeBallast(flags: 0x80)

    let result: DeviceTurnOnResult = try await ballast.turnOn(outputs: ["relay2"])

    #expect(result.group == 1)
    #expect(result.level == nil)
    // Get Operating Flags 0x05, whose reply holds relay mode, then Light On with relay 2's bit.
    #expect(await modem.standardCommands == [Command(command1: 0x1F, command2: 0x05), Command(command1: 0x11, command2: 0x02)])

  }

  @Test(.timeLimit(.minutes(1))) func switchesBothRelaysByTheirBitsORedTogether() async throws {

    let (ballast, modem): (Device, SettingsModem) = try makeBallast(flags: 0x80)

    _ = try await ballast.turnOn(outputs: ["Relay 1", "relay2"])
    try await ballast.turnOff(outputs: ["relay1"])

    #expect(await modem.standardCommands.filter { (command: Command) -> Bool in command.command1 != 0x1F } == [
      Command(command1: 0x11, command2: 0x03),
      Command(command1: 0x13, command2: 0x01)
    ])

  }

  @Test(.timeLimit(.minutes(1))) func switchesNoOutputOutsideRelayMode() async throws {

    let (ballast, modem): (Device, SettingsModem) = try makeBallast(flags: 0x00)

    do {

      _ = try await ballast.turnOn(outputs: ["relay1"])
      Issue.record("Expected outputsInactive.")

    } catch let DeviceControlError.outputsInactive(group, _) {

      #expect(group == 1)

    }

    // Only relay mode's flags byte was read.
    #expect(await modem.standardCommands == [Command(command1: 0x1F, command2: 0x05)])

  }

  @Test(.timeLimit(.minutes(1))) func refusesAnOutputTheGroupDoesntHave() async throws {

    let (ballast, modem): (Device, SettingsModem) = try makeBallast(flags: 0x80)

    do {

      _ = try await ballast.turnOn(outputs: ["relay3"])
      Issue.record("Expected noSuchOutput.")

    } catch let DeviceControlError.noSuchOutput(name, group, _) {

      #expect(name == "relay3")
      #expect(group == 1)

    }

    #expect(await modem.standardCommands.isEmpty)

  }

  @Test(.timeLimit(.minutes(1))) func listsTheBallastDimmersOutputs() async throws {

    let (ballast, _): (Device, SettingsModem) = try makeBallast(flags: 0x80)

    let load: DeviceGroup = try #require(try await ballast.capabilities().group(1))

    #expect(load.outputs == [DeviceOutput(key: "relay1", label: "Relay 1"), DeviceOutput(key: "relay2", label: "Relay 2")])
    #expect(load.outputsActiveWhen == DeviceFlagCondition(flag: "relayMode", isSet: true))
    #expect(load.armModes.isEmpty)

  }

  // MARK: - Arm modes

  @Test(.timeLimit(.minutes(1))) func exposesTheSirensArmModes() async throws {

    let address = InsteonAddress(0x6C, 0x7D, 0x02)
    let network = DeviceNetwork(
      modem: InMemoryModem(),
      catalog: try DeviceCatalog.bundled(),
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [address: ReportedIdentity(category: 0x07, subcategory: 0x1E, firmwareVersion: 0x41)])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    )

    let capabilities: DeviceCapabilities = try await network.device(address).capabilities()
    let modes: [Int: [String]] = Dictionary(uniqueKeysWithValues: capabilities.groups.map { (group: DeviceGroup) -> (Int, [String]) in (group.number, group.armModes) })

    #expect(modes == [1: ["away"], 2: ["away"], 3: ["home"], 4: ["home"], 5: ["home", "away"], 6: ["home", "away"]])
    #expect(capabilities.groups.first?.kind == .alarm)
    #expect(capabilities.groups.dropFirst().first?.kind == .arming)

  }

}

extension DeviceCapabilities {

  /// The group with a number, if the device has it.
  func group(_ number: Int) -> DeviceGroup? {

    groups.first { (group: DeviceGroup) -> Bool in group.number == number }

  }

}
