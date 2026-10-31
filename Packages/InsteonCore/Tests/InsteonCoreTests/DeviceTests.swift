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

    let result: DeviceBeepResult = try await self.network(modem).device(ControlExample.dimmer).beep()

    #expect(result.isListed)
    #expect(await commands(sentTo: ControlExample.dimmer, by: modem) == [Command(command1: 0x30, command2: 0x00)])

  }

  @Test func turnsADimmerOnAndOffFastAndChangesItsLevelAtOnce() async throws {

    let modem = InMemoryModem()
    let network: DeviceNetwork = self.network(modem)
    let lamp: Device = network.device(ControlExample.dimmer)

    let on: DeviceTurnOnResult = try await lamp.turnOnFast(level: 50)
    let off: DeviceTurnOffResult = try await lamp.turnOffFast()
    let instant: DeviceInstantChangeResult = try await lamp.changeInstantly(to: 25)

    #expect(on == DeviceTurnOnResult(group: 1, level: 50, ignoredLevel: nil, isCommandDescribed: true))
    #expect(off == DeviceTurnOffResult(group: 1, isCommandDescribed: true))
    #expect(instant == DeviceInstantChangeResult(group: 1, level: 25, isOnOffOnly: false, isCommandDescribed: true))
    #expect(await commands(sentTo: ControlExample.dimmer, by: modem) == [
      Command(command1: 0x12, command2: 0x80),
      Command(command1: 0x14, command2: 0x00),
      Command(command1: 0x21, command2: 0x40)
    ])
    #expect(await network.state(of: ControlExample.dimmer)?.level == 0x40)

  }

  @Test func clampsTheLevelToTheOneSent() async throws {

    let modem = InMemoryModem()

    let result: DeviceTurnOnResult = try await self.network(modem).device(ControlExample.dimmer).turnOn(level: 150)

    #expect(result.level == 100)
    #expect(await commands(sentTo: ControlExample.dimmer, by: modem) == [Command(command1: 0x11, command2: 0xFF)])

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

  @Test func beepsADeviceWhoseCommandSetDoesntListBeepAndSaysSo() async throws {

    let modem = InMemoryModem()
    let relay: Device = self.network(modem).device(ControlExample.relay)

    #expect(try await relay.capabilities().canBeep == false)

    let result: DeviceBeepResult = try await relay.beep()

    #expect(result == DeviceBeepResult(isListed: false))
    #expect(await commands(sentTo: ControlExample.relay, by: modem) == [Command(command1: 0x30, command2: 0x00)])

  }

  @Test func beepsADeviceThatIsntLinkedToTheModem() async throws {

    let modem = InMemoryModem()
    await modem.setUnlinked(ControlExample.unidentified)

    let result: DeviceBeepResult = try await self.network(modem).device(ControlExample.unidentified).beep()

    #expect(result.isListed == false)
    #expect(await commands(sentTo: ControlExample.unidentified, by: modem).contains(Command(command1: 0x30, command2: 0x00)))

  }

  @Test func changesARelayAtOnceWithItsOnAndOffActions() async throws {

    let modem = InMemoryModem()
    let relay: Device = self.network(modem).device(ControlExample.relay)

    let on: DeviceInstantChangeResult = try await relay.changeInstantly(to: 40)
    let off: DeviceInstantChangeResult = try await relay.changeInstantly(to: 0)

    #expect(on == DeviceInstantChangeResult(group: 1, level: 40, isOnOffOnly: true, isCommandDescribed: true))
    #expect(off.isOnOffOnly)
    #expect(await commands(sentTo: ControlExample.relay, by: modem) == [
      Command(command1: 0x11, command2: 0xFF),
      Command(command1: 0x13, command2: 0x00)
    ])

  }

  @Test func refusesLightOnFastToADeviceWhoseCommandSetDoesntListIt() async throws {

    let modem = InMemoryModem()
    let relay: Device = self.network(modem).device(ControlExample.relay)

    await #expect(throws: DeviceControlError.unsupported(.turnOnFast, product: "Example Relay 9102")) {

      _ = try await relay.turnOnFast()

    }

    #expect(await commands(sentTo: ControlExample.relay, by: modem).isEmpty)

  }

  @Test func sendsTheProtocolsLightOnFastToADeviceWhoseCommandsArentDescribed() async throws {

    let modem = InMemoryModem()

    let result: DeviceTurnOnResult = try await self.network(modem).device(ControlExample.unknownRelay).turnOnFast(level: 50)

    #expect(result == DeviceTurnOnResult(group: 1, level: nil, ignoredLevel: 50, isCommandDescribed: false))
    #expect(await commands(sentTo: ControlExample.unknownRelay, by: modem) == [Command(command1: 0x12, command2: 0xFF)])

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

    let modem = SettingsModem(device: ControlExample.fan, flags: 0x00, values: [:])
    let fan: Device = self.network(modem).device(ControlExample.fan)

    try await fan.turnOff(group: 2)

    await #expect(throws: DeviceControlError.unsupported(.turnOn, product: "Example Fan 9103")) {

      _ = try await fan.turnOn(group: 2)

    }

    let capabilities: DeviceCapabilities = try await fan.capabilities()
    var userData = UserData()
    userData[1] = 0x02

    // The fan's Off is an extended command with the fan's group in D1.
    #expect(await modem.extendedMessages == [
      ExtendedMessage(to: ControlExample.fan, command: Command(command1: 0x13, command2: 0x00), userData: userData, integrity: UnprotectedIntegrity())
    ])
    #expect(await modem.standardCommands.isEmpty)
    #expect(capabilities.groups.map(\.kind) == [.dimmer, .fan])
    #expect(capabilities.groups.last?.actionLabels == ["Off", "High"])
    #expect(capabilities.groups.last?.canDim == false)
    #expect(capabilities.groups.last?.canTurnOnAndOff == false)
    #expect(capabilities.groups.last?.hasStatus == true)

  }

  @Test func turnsTheLightOfAFanOnWithAStandardCommand() async throws {

    let modem = SettingsModem(device: ControlExample.fan, flags: 0x00, values: [:])

    let result: DeviceTurnOnResult = try await self.network(modem).device(ControlExample.fan).turnOn(level: 50)

    #expect(result == DeviceTurnOnResult(group: 1, level: 50, ignoredLevel: nil))
    #expect(await modem.standardCommands == [Command(command1: 0x11, command2: 0x80)])
    #expect(await modem.extendedMessages.isEmpty)

  }

  // MARK: - A device with several groups

  @Test func controlsEachOutletWithItsOwnCommands() async throws {

    let modem = SettingsModem(device: ControlExample.outlet, flags: 0x00, values: [:])
    let outlet: Device = self.network(modem).device(ControlExample.outlet)

    let top: DeviceTurnOnResult = try await outlet.turnOn(level: 30)
    let bottom: DeviceTurnOnResult = try await outlet.turnOn(group: 2)
    try await outlet.turnOff(group: 2)

    var userData = UserData()
    userData[1] = 0x02

    #expect(top == DeviceTurnOnResult(group: 1, level: nil, ignoredLevel: 30))
    #expect(bottom == DeviceTurnOnResult(group: 2, level: nil, ignoredLevel: nil))
    #expect(await modem.standardCommands == [Command(command1: 0x11, command2: 0xFF)])

    // The bottom outlet's commands are extended, with its group in D1 and a checksum in D14.
    let sent: [ExtendedMessage] = await modem.extendedMessages

    #expect(sent == [
      ExtendedMessage(to: ControlExample.outlet, command: Command(command1: 0x11, command2: 0xFF), userData: userData, integrity: ChecksumIntegrity()),
      ExtendedMessage(to: ControlExample.outlet, command: Command(command1: 0x13, command2: 0x00), userData: userData, integrity: ChecksumIntegrity())
    ])
    #expect(sent.first?.userData[14] == 0xEE)
    #expect(try await outlet.capabilities().groups.map(\.canTurnOnAndOff) == [true, true])

  }

  @Test func refusesAGroupItsCommandCantReachApartFromTheMainGroup() async throws {

    let modem = InMemoryModem()
    let keypad: Device = self.network(modem).device(ControlExample.keypad)

    await #expect(throws: DeviceControlError.unaddressable(.turnOn, group: 2, product: "Example Keypad 9105")) {

      _ = try await keypad.turnOn(group: 2)

    }

    await #expect(throws: DeviceControlError.unaddressable(.turnOff, group: 2, product: "Example Keypad 9105")) {

      try await keypad.turnOff(group: 2)

    }

    await #expect(throws: DeviceControlError.unaddressable(.status, group: 2, product: "Example Keypad 9105")) {

      _ = try await keypad.status(group: 2)

    }

    let capabilities: DeviceCapabilities = try await keypad.capabilities()

    #expect(await commands(sentTo: ControlExample.keypad, by: modem).isEmpty)
    #expect(capabilities.groups.map(\.canTurnOnAndOff) == [true, false])
    #expect(capabilities.groups.map(\.hasStatus) == [true, false])
    #expect(capabilities.groups.map(\.canDim) == [true, false])

    _ = try await keypad.turnOn(level: 50)

    #expect(await commands(sentTo: ControlExample.keypad, by: modem) == [Command(command1: 0x11, command2: 0x80)])

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
    let network: DeviceNetwork = self.network(modem)
    let device: Device = network.device(ControlExample.unknownOther)

    try await device.ping()
    let status: DeviceStatus = try await device.status()

    #expect(status.reading == .raw)
    #expect(status.value == 0x40)
    #expect(status.group == nil)
    #expect(try await device.capabilities().source == .uncontrolled)
    // Nothing says the raw byte is the device's level, so only when it answered is recorded.
    #expect(await network.state(of: ControlExample.unknownOther)?.level == nil)
    #expect(await network.state(of: ControlExample.unknownOther)?.lastSeen != nil)

    await #expect(throws: DeviceControlError.unsupported(.turnOn, product: "category 0x07, subcategory 0x55")) {

      _ = try await device.turnOn()

    }

    await #expect(throws: DeviceControlError.unsupported(.turnOff, product: "category 0x07, subcategory 0x55")) {

      try await device.turnOff()

    }

  }

  @Test func saysADeviceThatRejectsTheModemIsntLinked() async throws {

    let modem = InMemoryModem()
    await modem.setUnlinked(ControlExample.unidentified)
    let asked = Count()
    let device: Device = self.network(modem).device(ControlExample.unidentified, beforeIdentifying: { () -> Void in asked.increment() })

    await #expect(throws: DeviceControlError.notLinked) {

      _ = try await device.turnOn()

    }

    await #expect(throws: DeviceControlError.notLinked) {

      _ = try await device.status()

    }

    #expect(asked.value == 2)
    #expect(await commands(sentTo: ControlExample.unidentified, by: modem).allSatisfy { (command: Command) -> Bool in command.command1 == 0x0D })

  }

  @Test(.timeLimit(.minutes(1))) func refusesToTurnOnADeviceThatDoesntReportItsIdentity() async throws {

    let modem = InMemoryModem()
    let device: Device = self.network(modem).device(ControlExample.unidentified)

    // The device answers but sends no identity, so the wait for it ends at its timeout on the
    // test's clock.
    let turningOn = Task { () async throws -> DeviceTurnOnResult in try await device.turnOn() }

    await clock.waitForSleeper(until: Modem.defaultRequestTimeout)
    clock.advance(by: Modem.defaultRequestTimeout)

    await #expect(throws: DeviceControlError.notIdentified(.turnOn)) {

      _ = try await turningOn.value

    }

  }

  @Test func passesOnAnErrorOfTheConnectionWhileAskingForTheIdentity() async throws {

    let device: Device = self.network(ClosedModem()).device(ControlExample.unidentified)

    await #expect(throws: ModemError.connectionClosed) {

      _ = try await device.deviceDescription()

    }

    await #expect(throws: ModemError.connectionClosed) {

      _ = try await device.turnOn()

    }

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

  @Test func recordsNoLevelForAGroupOtherThanTheMainOne() async throws {

    let modem = SettingsModem(device: ControlExample.outlet, flags: 0x00, values: [:])
    let network: DeviceNetwork = self.network(modem)

    _ = try await network.device(ControlExample.outlet).turnOn(group: 2)

    #expect(await network.state(of: ControlExample.outlet)?.level == nil)
    #expect(await network.state(of: ControlExample.outlet)?.lastSeen == firstTime)

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

  @Test(.timeLimit(.minutes(1))) func readsSettings() async throws {

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

  @Test(.timeLimit(.minutes(1))) func readsEachButtonsValues() async throws {

    let modem = SettingsModem(device: ControlExample.buttons, flags: 0x00, values: [8: 0xFF])
    await modem.setValues([8: 0x80], ofButton: 0x02)
    await modem.setValues([8: 0x00], ofButton: 0x03)

    let reading: DeviceSettingsReading = try await self.network(modem).device(ControlExample.buttons).readSettings()

    #expect(reading.buttons == [0x01, 0x02, 0x03])
    #expect(reading.values[0x01]?["onLevel"] == 0xFF)
    #expect(reading.values[0x02]?["onLevel"] == 0x80)
    #expect(reading.values[0x03]?["onLevel"] == 0x00)

  }

  @Test(.timeLimit(.minutes(1))) func writesOneButtonsValueAndReadsItBack() async throws {

    let modem = SettingsModem(device: ControlExample.buttons, flags: 0x00, values: [8: 0xFF])
    await modem.setValues([8: 0x80], ofButton: 0x02)

    let change: DeviceSettingChange = try await self.network(modem).device(ControlExample.buttons).writeSetting("onLevel", to: "0x40", button: 2)
    let set: ExtendedMessage? = await modem.extendedMessages.first { (message: ExtendedMessage) -> Bool in message.userData[2] == 0x06 }

    #expect(change.button == 2)
    #expect(change.before != nil)
    #expect(change.isConfirmed)
    #expect(set?.userData[1] == 0x02)
    #expect(set?.userData[3] == 0x40)
    #expect(await modem.buttonValues[0x02]?[8] == 0x40)
    #expect(await modem.values[8] == 0xFF)

  }

  @Test func writesAFlagToAnI2CSDeviceAsAnExtendedMessageWithAChecksum() async throws {

    let modem = SettingsModem(device: ControlExample.buttons, flags: 0x02, values: [:])
    await modem.setEngine(.i2cs)

    let change: DeviceSettingChange = try await self.network(modem).device(ControlExample.buttons).writeSetting("keyBeep", to: "off")

    #expect(change.isConfirmed)
    #expect(await modem.flags == 0x00)
    #expect(await modem.extendedMessages == [
      ExtendedMessage(to: ControlExample.buttons, command: Command(command1: 0x20, command2: 0x0B), integrity: ChecksumIntegrity())
    ])
    #expect(await modem.standardCommands.contains(Command(command1: 0x20, command2: 0x0B)) == false)

  }

  @Test func writesAFlagAsAnExtendedMessageWhileItsGuardingFlagIsSet() async throws {

    // The program lock, bit 0x01, is set, so the key beep is set with the command repeated in
    // D1 and D2.
    let modem = SettingsModem(device: ControlExample.buttons, flags: 0x03, values: [:])

    let change: DeviceSettingChange = try await self.network(modem).device(ControlExample.buttons).writeSetting("keyBeep", to: "off")
    var userData = UserData()
    userData[1] = 0x20
    userData[2] = 0x0B

    #expect(change.after == "off")
    #expect(await modem.flags == 0x01)
    #expect(await modem.extendedMessages == [
      ExtendedMessage(to: ControlExample.buttons, command: Command(command1: 0x20, command2: 0x0B), userData: userData, integrity: UnprotectedIntegrity())
    ])

  }

  @Test func sendsAFlagAsAStandardMessageWhileItsGuardingFlagIsClear() async throws {

    let modem = SettingsModem(device: ControlExample.buttons, flags: 0x02, values: [:])

    _ = try await self.network(modem).device(ControlExample.buttons).writeSetting("keyBeep", to: "off")

    #expect(await modem.extendedMessages.isEmpty)
    #expect(await modem.standardCommands.contains(Command(command1: 0x20, command2: 0x0B)))

  }

  @Test func refusesAFlagWhenTheDeviceRejectsGetInsteonEngineVersion() async throws {

    let modem = SettingsModem(device: ControlExample.buttons, flags: 0x02, values: [:])
    await modem.rejectEngineRequests()

    let buttons: Device = self.network(modem).device(ControlExample.buttons)

    let error: DeviceSettingError? = await #expect(throws: DeviceSettingError.self) {

      _ = try await buttons.writeSetting("keyBeep", to: "off")

    }

    guard case .engineRejected? = error else {

      Issue.record("Expected engineRejected, got \(String(describing: error)).")

      return

    }

    #expect(await modem.flags == 0x02)

  }

  @Test(.timeLimit(.minutes(1))) func writesAFlagAndReadsItBack() async throws {

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

  @Test(.timeLimit(.minutes(1))) func writesAValueAndReadsItBack() async throws {

    let modem = SettingsModem(device: ControlExample.dimmer, flags: 0x00, values: [7: 0x1C, 8: 0xFF])

    let change: DeviceSettingChange = try await self.network(modem).device(ControlExample.dimmer).writeSetting("rampRate", to: "0.1 s")
    let set: ExtendedMessage? = await modem.extendedMessages.first { (message: ExtendedMessage) -> Bool in message.userData[2] == 0x05 }

    #expect(change.before == "0.5 s")
    #expect(change.after == "0.1 s")
    #expect(change.button == nil)
    #expect(await modem.values[7] == 0x1F)
    #expect(set?.userData[3] == 0x1F)

  }

  @Test(.timeLimit(.minutes(1))) func refusesAWriteTheDeviceDoesntKeep() async throws {

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

  @Test(.timeLimit(.minutes(1))) func refusesASettingTheCatalogDoesntHave() async throws {

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

  @Test(.timeLimit(.minutes(1))) func refusesSettingsOfADeviceWithoutACommandSet() async throws {

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

/// A modem whose connection is closed: every request fails with `ModemError.connectionClosed`.
struct ClosedModem: LinkingModem {

  func send(_ command: SerialCommand) async throws {

    throw ModemError.connectionClosed

  }

  func modemInfo() async throws -> ModemInfo {

    throw ModemError.connectionClosed

  }

  func request(_ message: StandardMessage, timeout: Duration) async throws -> ReceivedMessage {

    throw ModemError.connectionClosed

  }

  func request(_ message: ExtendedMessage, timeout: Duration) async throws -> ReceivedMessage {

    throw ModemError.connectionClosed

  }

  func readAllLinkDatabase(of device: InsteonAddress, timeout: Duration) async throws -> [AllLinkRecordResponse] {

    throw ModemError.connectionClosed

  }

  func readAllLinkRecord(of device: InsteonAddress, at address: UInt16, timeout: Duration) async throws -> AllLinkRecordResponse {

    throw ModemError.connectionClosed

  }

  func allLinkRecords(group: AllLinkGroupNumber, device: InsteonAddress) async throws -> [AllLinkRecord] {

    throw ModemError.connectionClosed

  }

  func allLinkRecords() async throws -> [AllLinkRecord] {

    throw ModemError.connectionClosed

  }

  func replies() async -> AsyncStream<ModemReply> {

    let (stream, continuation): (AsyncStream<ModemReply>, AsyncStream<ModemReply>.Continuation) = AsyncStream<ModemReply>.makeStream()
    continuation.finish()

    return stream

  }

}
