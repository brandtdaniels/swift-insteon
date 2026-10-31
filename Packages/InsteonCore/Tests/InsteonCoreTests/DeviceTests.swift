import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Devices of ``ControlExample``'s made-up catalog, controlled through ``Device`` on an
/// in-memory modem, a ``TestClock`` and fixed times.
struct DeviceTests {

  let clock: TestClock = TestClock()

  let times: FixedTimes = FixedTimes()

  /// The first time a network records, when nothing was identified first.
  let firstTime = Date(timeIntervalSince1970: 1_800_000_000)

  /// A network whose registry knows every device of the example catalog but the unidentified
  /// one.
  func network(_ modem: any LinkingModem, identities: [InsteonAddress: ReportedIdentity] = ControlExample.identities) -> DeviceNetwork {

    let times: FixedTimes = self.times

    return DeviceNetwork(
      modem: modem,
      catalog: ControlExample.catalog,
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: identities)),
      clock: clock,
      now: { () -> Date in times.now() }
    )

  }

  /// The commands the in-memory modem sent a device, in order, other than status requests.
  func commands(sentTo device: InsteonAddress, by modem: InMemoryModem) async -> [Command] {

    await modem.linkingSteps.compactMap { (step: InMemoryModem.LinkingStep) -> Command? in

      guard case let .device(address, command, _) = step, address == device else {

        return nil

      }

      return command

    }

  }

  // MARK: - A dimmer

  @Test func turnsADimmerOnAtALevel() async throws {

    let modem = InMemoryModem()
    let network: DeviceNetwork = self.network(modem)

    let result: DeviceTurnOnResult = try await network.device(ControlExample.dimmer).turnOn(level: 50)

    #expect(result == DeviceTurnOnResult(group: 1, level: 50, ignoredLevel: nil))
    #expect(await commands(sentTo: ControlExample.dimmer, by: modem) == [Command(command1: 0x11, command2: 0x80)])
    #expect(await modem.levels[ControlExample.dimmer] == 0x80)

  }

  @Test func turnsADimmerFullyOnWithoutALevelAndOff() async throws {

    let modem = InMemoryModem()
    let lamp: Device = self.network(modem).device(ControlExample.dimmer)

    let result: DeviceTurnOnResult = try await lamp.turnOn()
    try await lamp.turnOff()

    #expect(result == DeviceTurnOnResult(group: 1, level: nil, ignoredLevel: nil))
    #expect(await commands(sentTo: ControlExample.dimmer, by: modem) == [
      Command(command1: 0x11, command2: 0xFF),
      Command(command1: 0x13, command2: 0x00)
    ])

  }

  @Test func readsADimmersStatusAsAPercentage() async throws {

    let modem = InMemoryModem()
    await modem.setLevel(0x80, of: ControlExample.dimmer)

    let status: DeviceStatus = try await self.network(modem).device(ControlExample.dimmer).status()

    #expect(status.reading == .percent(50))
    #expect(status.percent == 50)
    #expect(status.value == 0x80)
    #expect(status.isOn)
    #expect(status.group == 1)

  }

  @Test func describesADimmersCapabilities() async throws {

    let capabilities: DeviceCapabilities = try await self.network(InMemoryModem()).device(ControlExample.dimmer).capabilities()

    #expect(capabilities.source == .catalog)
    #expect(capabilities.isIdentified)
    #expect(capabilities.productName == "Example Dimmer 9101")
    #expect(capabilities.canDim)
    #expect(capabilities.canTurnOnAndOff)
    #expect(capabilities.canBeep)
    #expect(capabilities.mainGroup?.kind == .dimmer)
    #expect(capabilities.settings.map(\.key) == ["rampRate", "onLevel", "keyBeep"])
    #expect(capabilities.settings.first?.control == .choice(["0.5 s", "0.1 s"]))
    #expect(capabilities.settings.last?.control == .toggle)

  }

  @Test func beepsADeviceWhoseCommandSetListsBeep() async throws {

    let modem = InMemoryModem()

    try await self.network(modem).device(ControlExample.dimmer).beep()

    #expect(await commands(sentTo: ControlExample.dimmer, by: modem) == [Command(command1: 0x30, command2: 0x00)])

  }

  // MARK: - Status decoding

  @Test func readsEveryLevelAsTheSamePercentageAsLightLevel() throws {

    let model = DeviceControlModel.make(ControlExample.catalog.describe(category: 0x01, subcategory: 0x7C, firmwareVersion: 0x45))
    let group: DeviceControlModel.Group = try #require(model.mainGroup)

    for byte in 0...255 {

      let value = UInt8(byte)
      let reading: (reading: DeviceStatus.Reading, isOn: Bool) = Device.reading(of: value, group: group, in: model, reply: ControlExample.readLevel.reply)

      #expect(reading.reading == .percent(LightLevel.percent(level: value)))
      #expect(reading.isOn == (value != 0))

    }

  }

  @Test func readsARelaysStatusByItsRanges() throws {

    let model = DeviceControlModel.make(ControlExample.catalog.describe(category: 0x02, subcategory: 0x7D, firmwareVersion: 0x45))
    let group: DeviceControlModel.Group = try #require(model.mainGroup)

    #expect(Device.reading(of: 0x00, group: group, in: model, reply: nil).reading == .named("Off"))
    #expect(Device.reading(of: 0xFF, group: group, in: model, reply: nil).reading == .named("On"))
    #expect(Device.reading(of: 0x01, group: group, in: model, reply: nil).isOn)

  }

  // MARK: - A relay

  @Test func turnsARelayFullyOnAndReportsTheLevelItIgnored() async throws {

    let modem = InMemoryModem()
    let network: DeviceNetwork = self.network(modem)

    let result: DeviceTurnOnResult = try await network.device(ControlExample.relay).turnOn(level: 50)

    #expect(result == DeviceTurnOnResult(group: 1, level: nil, ignoredLevel: 50))
    #expect(await commands(sentTo: ControlExample.relay, by: modem) == [Command(command1: 0x11, command2: 0xFF)])
    #expect(await network.state(of: ControlExample.relay)?.level == 0xFF)

  }

  @Test func readsARelaysStatusAsTheNameOfItsRange() async throws {

    let modem = InMemoryModem()
    await modem.setLevel(0xFF, of: ControlExample.relay)

    let status: DeviceStatus = try await self.network(modem).device(ControlExample.relay).status()

    #expect(status.reading == .named("On"))
    #expect(status.percent == nil)
    #expect(status.isOn)

  }

  @Test func refusesBeepToADeviceWhoseCommandSetDoesntListIt() async throws {

    let modem = InMemoryModem()
    let relay: Device = self.network(modem).device(ControlExample.relay)

    #expect(try await relay.capabilities().canBeep == false)

    await #expect(throws: DeviceControlError.unsupported(.beep, product: "Example Relay 9102")) {

      try await relay.beep()

    }

    #expect(await commands(sentTo: ControlExample.relay, by: modem).isEmpty)

  }

  // MARK: - A fan with a light

  @Test func readsAFansSpeedByItsRanges() async throws {

    let modem = InMemoryModem()
    await modem.setLevel(0x80, of: ControlExample.fan)
    let fan: Device = self.network(modem).device(ControlExample.fan)

    let light: DeviceStatus = try await fan.status()
    let speed: DeviceStatus = try await fan.status(group: 2)

    #expect(light.reading == .percent(50))
    #expect(speed.reading == .named("Medium"))
    #expect(speed.group == 2)

  }

  @Test func turnsAFanOffButNotOnWithoutAnOnAction() async throws {

    let modem = InMemoryModem()
    let fan: Device = self.network(modem).device(ControlExample.fan)

    try await fan.turnOff(group: 2)

    await #expect(throws: DeviceControlError.unsupported(.turnOn, product: "Example Fan 9103")) {

      _ = try await fan.turnOn(group: 2)

    }

    let capabilities: DeviceCapabilities = try await fan.capabilities()

    #expect(await commands(sentTo: ControlExample.fan, by: modem) == [Command(command1: 0x13, command2: 0x02)])
    #expect(capabilities.groups.map(\.kind) == [.dimmer, .fan])
    #expect(capabilities.groups.last?.actionLabels == ["Off", "High"])
    #expect(capabilities.groups.last?.canDim == false)

  }

  // MARK: - A device with several groups

  @Test func controlsEachOutletWithItsOwnCommands() async throws {

    let modem = InMemoryModem()
    let outlet: Device = self.network(modem).device(ControlExample.outlet)

    let top: DeviceTurnOnResult = try await outlet.turnOn(level: 30)
    let bottom: DeviceTurnOnResult = try await outlet.turnOn(group: 2)
    try await outlet.turnOff(group: 2)

    #expect(top == DeviceTurnOnResult(group: 1, level: nil, ignoredLevel: 30))
    #expect(bottom == DeviceTurnOnResult(group: 2, level: nil, ignoredLevel: nil))
    #expect(await commands(sentTo: ControlExample.outlet, by: modem) == [
      Command(command1: 0x11, command2: 0xFF),
      Command(command1: 0x32, command2: 0x02),
      Command(command1: 0x33, command2: 0x02)
    ])

  }

  @Test func readsEachOutletsBit() async throws {

    let modem = InMemoryModem()
    await modem.setLevel(0x02, of: ControlExample.outlet)
    let network: DeviceNetwork = self.network(modem)
    let outlet: Device = network.device(ControlExample.outlet)

    let top: DeviceStatus = try await outlet.status(group: 1)
    let bottom: DeviceStatus = try await outlet.status(group: 2)

    #expect(top.reading == .onOff(false))
    #expect(top.isOn == false)
    #expect(bottom.reading == .onOff(true))
    #expect(bottom.isOn)
    // A bit of the reply isn't the device's level, so only when it answered is recorded.
    #expect(await network.state(of: ControlExample.outlet)?.level == nil)
    #expect(await network.state(of: ControlExample.outlet)?.lastSeen != nil)

  }

  @Test func refusesAGroupTheDeviceDoesntHave() async throws {

    let outlet: Device = self.network(InMemoryModem()).device(ControlExample.outlet)

    await #expect(throws: DeviceControlError.noSuchGroup(3, product: "Example Outlet 9104")) {

      _ = try await outlet.turnOn(group: 3)

    }

  }

  // MARK: - Devices the catalog doesn't describe

  @Test func controlsAnUnknownDimmerByItsCategory() async throws {

    let modem = InMemoryModem()
    await modem.setLevel(0x40, of: ControlExample.unknownDimmer)
    let device: Device = self.network(modem).device(ControlExample.unknownDimmer)

    let status: DeviceStatus = try await device.status()
    let result: DeviceTurnOnResult = try await device.turnOn(level: 50)
    let capabilities: DeviceCapabilities = try await device.capabilities()

    #expect(status.reading == .percent(25))
    #expect(result == DeviceTurnOnResult(group: 1, level: 50, ignoredLevel: nil))
    #expect(await commands(sentTo: ControlExample.unknownDimmer, by: modem) == [Command(command1: 0x11, command2: 0x80)])
    #expect(capabilities.source == .categoryFallback)
    #expect(capabilities.canDim)
    #expect(capabilities.productName == nil)

  }

  @Test func controlsAnUnknownRelayByItsCategory() async throws {

    let modem = InMemoryModem()
    let device: Device = self.network(modem).device(ControlExample.unknownRelay)

    let result: DeviceTurnOnResult = try await device.turnOn(level: 50)
    let status: DeviceStatus = try await device.status()

    #expect(result == DeviceTurnOnResult(group: 1, level: nil, ignoredLevel: 50))
    #expect(status.reading == .named("On"))
    #expect(try await device.capabilities().canDim == false)

  }

  @Test func onlyPingsAndReadsTheRawStatusOfAnUnknownDeviceOfAnotherCategory() async throws {

    let modem = InMemoryModem()
    await modem.setLevel(0x40, of: ControlExample.unknownOther)
    let device: Device = self.network(modem).device(ControlExample.unknownOther)

    try await device.ping()
    let status: DeviceStatus = try await device.status()

    #expect(status.reading == .raw)
    #expect(status.value == 0x40)
    #expect(status.group == nil)
    #expect(try await device.capabilities().source == .uncontrolled)

    await #expect(throws: DeviceControlError.unsupported(.turnOn, product: "category 0x07, subcategory 0x55")) {

      _ = try await device.turnOn()

    }

    await #expect(throws: DeviceControlError.unsupported(.turnOff, product: "category 0x07, subcategory 0x55")) {

      try await device.turnOff()

    }

  }

  @Test func refusesToTurnOnADeviceThatDoesntReportItsIdentity() async throws {

    let modem = InMemoryModem()
    await modem.setUnlinked(ControlExample.unidentified)
    let asked = Count()
    let device: Device = self.network(modem).device(ControlExample.unidentified, beforeIdentifying: { () -> Void in asked.increment() })

    await #expect(throws: DeviceControlError.notIdentified(.turnOn)) {

      _ = try await device.turnOn()

    }

    #expect(asked.value == 1)
    #expect(try await device.capabilities().isIdentified == false)

  }

  @Test func identifiesADeviceTheRegistryDoesntKnowBeforeControllingIt() async throws {

    let modem = InMemoryModem()
    await modem.setIdentity(SetButtonPressed(sender: ControlExample.dimmer, role: .responder, category: 0x01, subcategory: 0x7C, firmwareVersion: 0x45))
    let asked = Count()
    let network: DeviceNetwork = self.network(modem, identities: [:])
    let lamp: Device = network.device(ControlExample.dimmer, beforeIdentifying: { () -> Void in asked.increment() })

    let result: DeviceTurnOnResult = try await lamp.turnOn(level: 50)
    _ = try await lamp.turnOn(level: 25)

    #expect(result.level == 50)
    #expect(asked.value == 1)
    #expect(await network.registry.device(ControlExample.dimmer)?.identity == ControlExample.dimmerIdentity)

  }

  // MARK: - The network's state

  @Test func recordsTheLevelAndWhenTheDeviceAnswered() async throws {

    let modem = InMemoryModem()
    let network: DeviceNetwork = self.network(modem)
    let lamp: Device = network.device(ControlExample.dimmer)

    _ = try await lamp.turnOn(level: 50)

    #expect(await network.state(of: ControlExample.dimmer)?.level == 0x80)
    #expect(await network.state(of: ControlExample.dimmer)?.lastSeen == firstTime)

    try await lamp.turnOff()

    #expect(await network.state(of: ControlExample.dimmer)?.level == 0x00)

    await modem.setLevel(0x40, of: ControlExample.dimmer)
    _ = try await lamp.status()

    let snapshot: NetworkSnapshot = await network.snapshot()

    #expect(snapshot.devices[ControlExample.dimmer]?.level == 0x40)
    #expect(snapshot.devices[ControlExample.dimmer]?.lastSeen == firstTime.addingTimeInterval(120))

  }

  @Test func savesWhatControlLearnedThroughAMerge() async throws {

    let modem = InMemoryModem()
    let start = NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: ControlExample.identities))
    let network: DeviceNetwork = self.network(modem)

    _ = try await network.device(ControlExample.relay).turnOn()

    let merged: NetworkSnapshot = start.merging(changesFrom: start, to: await network.snapshot())

    #expect(merged.devices[ControlExample.relay]?.level == 0xFF)
    #expect(merged.devices[ControlExample.relay]?.lastSeen == firstTime)

  }

  // MARK: - Settings

  @Test func readsSettings() async throws {

    let modem = SettingsModem(device: ControlExample.dimmer, flags: 0x02, values: [7: 0x1C, 8: 0xFF])
    let began = Count()

    let reading: DeviceSettingsReading = try await self.network(modem).device(ControlExample.dimmer).readSettings(beforeReading: { () -> Void in began.increment() })
    let texts: [String: String] = Dictionary(uniqueKeysWithValues: reading.entries.map { (entry: DeviceSettingsReading.Entry) -> (String, String) in

      (entry.setting.key, entry.text ?? "not reported")

    })

    #expect(began.value == 1)
    #expect(reading.operatingFlags[.operatingFlags] == 0x02)
    #expect(reading.values[0x01]?["rampRate"] == 0x1C)
    #expect(reading.buttons == [0x01])
    #expect(texts == ["keyBeep": "on", "rampRate": "0.5 s", "onLevel": "100%"])
    #expect(reading.entries.first(where: { (entry: DeviceSettingsReading.Entry) -> Bool in entry.setting.key == "keyBeep" })?.defaultText == "off")

  }

  @Test func writesAFlagAndReadsItBack() async throws {

    let modem = SettingsModem(device: ControlExample.dimmer, flags: 0x02, values: [:])

    let change: DeviceSettingChange = try await self.network(modem).device(ControlExample.dimmer).writeSetting("key beep", to: "off")

    #expect(change.before == "on")
    #expect(change.requested == "off")
    #expect(change.after == "off")
    #expect(change.isConfirmed)
    #expect(change.title == "Key beep")
    #expect(await modem.flags == 0x00)
    // The device runs i2, as Get Insteon Engine Version says, so Set Operating Flags is
    // standard.
    #expect(await modem.standardCommands.contains(Command(command1: 0x20, command2: 0x0B)))

  }

  @Test func writesAValueAndReadsItBack() async throws {

    let modem = SettingsModem(device: ControlExample.dimmer, flags: 0x00, values: [7: 0x1C, 8: 0xFF])

    let change: DeviceSettingChange = try await self.network(modem).device(ControlExample.dimmer).writeSetting("rampRate", to: "0.1 s")
    let set: ExtendedMessage? = await modem.extendedMessages.first { (message: ExtendedMessage) -> Bool in message.userData[2] == 0x05 }

    #expect(change.before == "0.5 s")
    #expect(change.after == "0.1 s")
    #expect(change.button == nil)
    #expect(await modem.values[7] == 0x1F)
    #expect(set?.userData[3] == 0x1F)

  }

  @Test func refusesAWriteTheDeviceDoesntKeep() async throws {

    let modem = SettingsModem(device: ControlExample.dimmer, flags: 0x00, values: [7: 0x1C, 8: 0xFF])
    await modem.ignoreWrites()
    let lamp: Device = self.network(modem).device(ControlExample.dimmer)

    let error: DeviceSettingError? = await #expect(throws: DeviceSettingError.self) {

      _ = try await lamp.writeSetting("rampRate", to: "0.1 s")

    }

    guard case let .notChanged(title, requested, reported)? = error else {

      Issue.record("Expected notChanged, got \(String(describing: error)).")

      return

    }

    #expect(title == "Ramp rate")
    #expect(requested == "0.1 s")
    #expect(reported == "0.5 s")

  }

  @Test func refusesASettingTheCatalogDoesntHave() async throws {

    let modem = SettingsModem(device: ControlExample.dimmer, flags: 0x00, values: [:])
    let lamp: Device = self.network(modem).device(ControlExample.dimmer)

    let error: DeviceSettingError? = await #expect(throws: DeviceSettingError.self) {

      _ = try await lamp.writeSetting("nightMode", to: "on")

    }

    guard case let .noSuchSetting(name, product)? = error else {

      Issue.record("Expected noSuchSetting, got \(String(describing: error)).")

      return

    }

    #expect(name == "nightMode")
    #expect(product == "Example Dimmer 9101")

    #expect(await modem.extendedMessages.isEmpty)

  }

  @Test func refusesSettingsOfADeviceWithoutACommandSet() async throws {

    let relay: Device = self.network(InMemoryModem()).device(ControlExample.unknownRelay)

    let error: DeviceSettingError? = await #expect(throws: DeviceSettingError.self) {

      _ = try await relay.readSettings()

    }

    guard case let .noSettings(product)? = error else {

      Issue.record("Expected noSettings, got \(String(describing: error)).")

      return

    }

    #expect(product == "category 0x02, subcategory 0x55")

  }

}
