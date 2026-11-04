import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// A made-up catalog whose devices change one setting when another is written: a lamp whose
/// linger time, once it isn't zero, turns its sparkle flag on, with a murmur reading and a hiss
/// value it reports but nothing writes; a panel whose hum flag turns its sparkle flag on, with a
/// drift flag of its own Get Operating Flags request; and keys whose shine and tint are per
/// button.
enum SideEffectExample {

  // MARK: - Addresses

  static let lamp = InsteonAddress(0x5C, 0x6D, 0x01)

  static let panel = InsteonAddress(0x5C, 0x6D, 0x02)

  static let single = InsteonAddress(0x5C, 0x6D, 0x03)

  static let keys = InsteonAddress(0x5C, 0x6D, 0x04)

  // MARK: - Identities

  static let lampIdentity = ReportedIdentity(category: 0x01, subcategory: 0x71, firmwareVersion: 0x45)

  static let panelIdentity = ReportedIdentity(category: 0x01, subcategory: 0x72, firmwareVersion: 0x45)

  static let singleIdentity = ReportedIdentity(category: 0x01, subcategory: 0x73, firmwareVersion: 0x45)

  static let keysIdentity = ReportedIdentity(category: 0x01, subcategory: 0x74, firmwareVersion: 0x45)

  static let identities: [InsteonAddress: ReportedIdentity] = [lamp: lampIdentity, panel: panelIdentity, single: singleIdentity, keys: keysIdentity]

  // MARK: - Settings

  static let hum = OperatingFlag(name: "hum", summary: "Hums.", query: .operatingFlags, bit: 0x02, on: 0x0A, off: 0x0B, label: "Hum")

  static let sparkle = OperatingFlag(name: "sparkle", summary: "Sparkles.", query: .operatingFlags, bit: 0x04, on: 0x04, off: 0x05, label: "Sparkle")

  static let drift = OperatingFlag(name: "drift", summary: "Drifts.", query: 0x01, bit: 0x01, on: 0x06, off: 0x07, label: "Drift")

  static let murmur = OperatingReading(name: "murmur", summary: "How much the device murmurs.", query: 0x02, label: "Murmur")

  /// The lamp's flags, a reading and three values, as ``SettingsModem`` keeps them: the linger
  /// time at D7, written with selector `0x05`, the glimmer at D8, written with selector `0x06`,
  /// and the hiss at D9, which nothing writes.
  static let lampCommands = CommandSet(
    id: "exampleSideEffectLamp",
    name: "Example side effect lamp",
    summary: "A linger time that turns the sparkle on.",
    operatingFlags: [hum, sparkle],
    readings: [murmur],
    extendedSettings: ExtendedSettings(
      isPerButton: false,
      values: [
        SettingValue(name: "lingerTime", summary: "How long the load lingers.", position: 7, label: "Linger time"),
        SettingValue(name: "glimmer", summary: "How much the load glimmers.", position: 8, label: "Glimmer"),
        SettingValue(name: "hiss", summary: "How much noise the device hears.", position: 9, label: "Hiss")
      ],
      writes: [
        SettingWrite(name: "lingerTime", summary: "Sets the linger time.", selector: 0x05, isPerButton: false, bytes: [SettingWrite.Byte(position: 3, value: "lingerTime")]),
        SettingWrite(name: "glimmer", summary: "Sets the glimmer.", selector: 0x06, isPerButton: false, bytes: [SettingWrite.Byte(position: 3, value: "glimmer")])
      ]
    ),
    standardCommands: [ControlExample.lightOn, ControlExample.lightOff, ControlExample.readLevel],
    groupTypes: [ControlExample.light]
  )

  /// Flags only, so the in-memory modem keeps them all.
  static let panelCommands = CommandSet(
    id: "exampleSideEffectPanel",
    name: "Example side effect panel",
    summary: "A hum that turns the sparkle on.",
    operatingFlags: [hum, sparkle, drift],
    standardCommands: [ControlExample.lightOn, ControlExample.lightOff, ControlExample.readLevel],
    groupTypes: [ControlExample.light]
  )

  /// One flag, so there's nothing else to compare.
  static let singleCommands = CommandSet(
    id: "exampleSideEffectSingle",
    name: "Example side effect single",
    summary: "One flag.",
    operatingFlags: [hum],
    standardCommands: [ControlExample.lightOn, ControlExample.lightOff, ControlExample.readLevel],
    groupTypes: [ControlExample.light]
  )

  /// Three buttons, each with a shine at D8, written with selector `0x06`, and a tint at D9,
  /// written with selector `0x07`.
  static let keysCommands = CommandSet(
    id: "exampleSideEffectKeys",
    name: "Example side effect keys",
    summary: "Per-button shine and tint.",
    extendedSettings: ExtendedSettings(
      isPerButton: true,
      values: [
        SettingValue(name: "shine", summary: "How bright a button shines.", position: 8, label: "Shine"),
        SettingValue(name: "tint", summary: "A button's tint.", position: 9, label: "Tint")
      ],
      writes: [
        SettingWrite(name: "shine", summary: "Sets a button's shine.", selector: 0x06, isPerButton: true, bytes: [SettingWrite.Byte(position: 3, value: "shine")]),
        SettingWrite(name: "tint", summary: "Sets a button's tint.", selector: 0x07, isPerButton: true, bytes: [SettingWrite.Byte(position: 3, value: "tint")])
      ]
    ),
    standardCommands: [ControlExample.lightOn, ControlExample.lightOff, ControlExample.readLevel],
    groupTypes: [ControlExample.light]
  )

  static let catalog = DeviceCatalog(
    profiles: [
      ControlExample.profile(model: "9201", name: "Example Lamp", identity: lampIdentity, commands: lampCommands, groups: [
        DeviceProfile.Group(number: 1, name: "Load", role: .both, type: "light")
      ]),
      ControlExample.profile(model: "9202", name: "Example Panel", identity: panelIdentity, commands: panelCommands, groups: [
        DeviceProfile.Group(number: 1, name: "Load", role: .both, type: "light")
      ]),
      ControlExample.profile(model: "9203", name: "Example Single", identity: singleIdentity, commands: singleCommands, groups: [
        DeviceProfile.Group(number: 1, name: "Load", role: .both, type: "light")
      ]),
      ControlExample.profile(model: "9204", name: "Example Keys", identity: keysIdentity, commands: keysCommands, groups: [
        DeviceProfile.Group(number: 1, name: "Button 1", role: .both, type: "light"),
        DeviceProfile.Group(number: 2, name: "Button 2", role: .controller),
        DeviceProfile.Group(number: 3, name: "Button 3", role: .controller)
      ])
    ],
    commandSets: [lampCommands, panelCommands, singleCommands, keysCommands]
  )

}

/// Writing a setting reports the other writable settings the write changed, by reading the
/// device's settings before and after it.
@Suite(.timeLimit(.minutes(1)))
struct SettingSideEffectTests {

  let clock: TestClock = TestClock()

  let times: FixedTimes = FixedTimes()

  func network(_ modem: any LinkingModem) -> DeviceNetwork {

    let times: FixedTimes = self.times

    return DeviceNetwork(
      modem: modem,
      catalog: SideEffectExample.catalog,
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: SideEffectExample.identities)),
      clock: clock,
      now: { () -> Date in times.now() }
    )

  }

  /// An in-memory modem with a panel whose hum is set with `0x0A` and cleared with `0x0B`, and
  /// whose Get Operating Flags requests `0x00` and `0x01` report the hum and sparkle bits and
  /// the drift bit.
  func panelModem(flags: UInt8, device: InsteonAddress = SideEffectExample.panel) async -> InMemoryModem {

    let modem = InMemoryModem()
    await modem.setOperatingFlags(flags, of: device)
    await modem.setOperatingFlagCommand(0x0A, bit: 0x02, isSet: true, of: device)
    await modem.setOperatingFlagCommand(0x0B, bit: 0x02, isSet: false, of: device)
    await modem.setOperatingFlagsMask(0x06, forQuery: 0x00, of: device)
    await modem.setOperatingFlagsMask(0x01, forQuery: 0x01, of: device)

    return modem

  }

  /// Each other setting's key, button, value before and value after.
  func changes(_ change: DeviceSettingChange) -> [[String]] {

    change.changedSettings.map { (other: DeviceSettingChange.OtherChange) -> [String] in

      [other.setting.key, other.button.map(String.init) ?? "-", other.before, other.after]

    }

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

  /// Makes Get Operating Flags requests fail with `error` once a Set Operating Flags has been
  /// sent: the request `query`, or any, after `skipping` of them have been answered.
  func failReads(of modem: InMemoryModem, query: UInt8? = nil, skipping: Int, with error: some Error & Sendable) async {

    let written = Count()
    let readsAfterWrite = Count()

    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      guard case let .standardRequest(message) = operation else {

        return

      }

      if message.command.command1 == 0x20 {

        written.increment()

      } else if message.command.command1 == 0x1F, written.value > 0, query == nil || message.command.command2 == query {

        readsAfterWrite.increment()

        if readsAfterWrite.value > skipping {

          throw error

        }

      }

    }

  }

  // MARK: - Reporting what else changed

  @Test func reportsAFlagAValueWriteTurnedOn() async throws {

    let modem = SettingsModem(device: SideEffectExample.lamp, flags: 0x00, values: [7: 0x00, 8: 0x10, 9: 0xA2])
    await modem.setFlagBits(0x04, whenWritingANonZeroValueWith: 0x05)

    let change: DeviceSettingChange = try await network(modem).device(SideEffectExample.lamp).writeSetting("lingerTime", to: "0x05")

    #expect(change.after == "0x05")
    #expect(change.otherSettings == .compared([
      DeviceSettingChange.OtherChange(
        setting: SettingPresentation.setting(for: SettingItem(flag: SideEffectExample.sparkle), in: SideEffectExample.lampCommands),
        button: nil,
        before: "off",
        after: "on"
      )
    ]))
    #expect(changes(change) == [["sparkle", "-", "off", "on"]])
    #expect(change.changedSettings.first?.title == "Sparkle")

  }

  @Test func leavesOutAReadOnlyValueThatChangesOnItsOwnAndReportsAWritableOne() async throws {

    let modem = SettingsModem(device: SideEffectExample.lamp, flags: 0x00, values: [7: 0x00, 8: 0x10, 9: 0xA2])
    await modem.changeValuesOnTheirOwn(at: [8, 9])

    let change: DeviceSettingChange = try await network(modem).device(SideEffectExample.lamp).writeSetting("hum", to: "on")

    #expect(change.after == "on")
    #expect(changes(change).map { (other: [String]) -> String in other[0] } == ["glimmer"])

  }

  @Test func reportsAFlagAFlagWriteTurnedOnAndNotTheFlagWritten() async throws {

    let modem: InMemoryModem = await panelModem(flags: 0x00)
    await modem.setOperatingFlagSideEffect(of: 0x0A, bit: 0x04, isSet: true, of: SideEffectExample.panel)

    let change: DeviceSettingChange = try await network(modem).device(SideEffectExample.panel).writeSetting("hum", to: "on")

    #expect(change.before == "off")
    #expect(change.after == "on")
    #expect(changes(change) == [["sparkle", "-", "off", "on"]])

  }

  @Test func reportsNothingElseWhenOnlyTheSettingWrittenChanged() async throws {

    let modem: InMemoryModem = await panelModem(flags: 0x04)

    let change: DeviceSettingChange = try await network(modem).device(SideEffectExample.panel).writeSetting("hum", to: "on")

    #expect(change.after == "on")
    #expect(change.otherSettings == .compared([]))
    #expect(change.changedSettings.isEmpty)
    #expect(change.unreadSettings.isEmpty)

  }

  @Test func reportsAnotherButtonsChangeWithItsButtonAndLeavesOutTheSettingWrittenOnEveryButton() async throws {

    let modem = SettingsModem(device: SideEffectExample.keys, flags: 0x00, values: [8: 0xFF, 9: 0x00])
    await modem.setValues([8: 0x80, 9: 0x00], ofButton: 0x02)
    await modem.setValues([8: 0x80, 9: 0x00], ofButton: 0x03)
    // Writing button 2's shine also writes button 1's shine and button 2's tint.
    await modem.setValueSideEffect(ofSelector: 0x06, writes: 0x11, at: 8, ofButton: 0x01)
    await modem.setValueSideEffect(ofSelector: 0x06, writes: 0x22, at: 9)

    let change: DeviceSettingChange = try await network(modem).device(SideEffectExample.keys).writeSetting("shine", to: "0x40", button: 2)

    #expect(change.button == 2)
    #expect(change.after == "0x40")
    #expect(changes(change) == [["tint", "2", "0x00", "0x22"]])
    #expect(change.changedSettings.first?.title == "Tint (button 2)")
    // Button 3 isn't read: only button 1 and the button written are compared.
    #expect(await modem.sent == [
      "2E 00 02 00 00",
      "2E 00 01 00 00",
      "2E 00 02 06 40",
      "2E 00 02 00 00",
      "2E 00 01 00 00"
    ])

  }

  // MARK: - What's sent

  @Test func readsEachRequestOnceAroundAFlagWrite() async throws {

    let modem: InMemoryModem = await panelModem(flags: 0x00)

    _ = try await network(modem).device(SideEffectExample.panel).writeSetting("hum", to: "on")

    #expect(await commands(sentTo: SideEffectExample.panel, by: modem) == [
      // The flag written, with the sparkle in the same byte.
      Command(command1: 0x1F, command2: 0x00),
      // The drift, before.
      Command(command1: 0x1F, command2: 0x01),
      // The write and its read-back, with the sparkle.
      Command(command1: 0x0D, command2: 0x00),
      Command(command1: 0x20, command2: 0x0A),
      Command(command1: 0x1F, command2: 0x00),
      // The drift, after.
      Command(command1: 0x1F, command2: 0x01)
    ])

  }

  @Test func readsEachRequestOnceAroundAFlagWriteToADeviceWithValues() async throws {

    let modem = SettingsModem(device: SideEffectExample.lamp, flags: 0x00, values: [7: 0x00, 8: 0x10, 9: 0xA2])

    _ = try await network(modem).device(SideEffectExample.lamp).writeSetting("hum", to: "on")

    // The murmur is a reading, so its request, 0x02, is never sent.
    #expect(await modem.sent == ["1F 00", "2E 00 01 00 00", "0D 00", "20 0A", "1F 00", "2E 00 01 00 00"])

  }

  @Test func readsEachRequestOnceAroundAValueWriteInOrder() async throws {

    let modem = SettingsModem(device: SideEffectExample.lamp, flags: 0x00, values: [7: 0x00, 8: 0x10, 9: 0xA2])

    _ = try await network(modem).device(SideEffectExample.lamp).writeSetting("lingerTime", to: "0x05")

    #expect(await modem.sent == [
      // The value written, with the glimmer and hiss in the same reply.
      "2E 00 01 00 00",
      // The flags, before.
      "1F 00",
      // The write and its read-back.
      "2E 00 01 05 05",
      "2E 00 01 00 00",
      // The flags, after.
      "1F 00"
    ])

  }

  // MARK: - Nothing to compare

  @Test func sendsNothingMoreWhenTheDeviceHasNoOtherSetting() async throws {

    let modem: InMemoryModem = await panelModem(flags: 0x00, device: SideEffectExample.single)

    let change: DeviceSettingChange = try await network(modem).device(SideEffectExample.single).writeSetting("hum", to: "on")

    #expect(change.after == "on")
    #expect(change.otherSettings == DeviceSettingChange.OtherSettings(outcome: .nothingToCompare))
    #expect(await commands(sentTo: SideEffectExample.single, by: modem) == [
      Command(command1: 0x1F, command2: 0x00),
      Command(command1: 0x0D, command2: 0x00),
      Command(command1: 0x20, command2: 0x0A),
      Command(command1: 0x1F, command2: 0x00)
    ])

  }

  @Test func readsNoOtherSettingWhenTheDeviceDoesntAnswerTheWritesOwnRead() async throws {

    let modem: InMemoryModem = await panelModem(flags: 0x00)
    let reads = Count()

    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      guard case let .standardRequest(message) = operation, message.command.command1 == 0x1F else {

        return

      }

      reads.increment()

      if reads.value == 1 {

        throw ModemError.deviceTimedOut(message.destination)

      }

    }

    let change: DeviceSettingChange = try await network(modem).device(SideEffectExample.panel).writeSetting("hum", to: "on")

    #expect(change.before == nil)
    #expect(change.after == "on")
    #expect(change.otherSettings == DeviceSettingChange.OtherSettings(outcome: .notReportedBefore))
    // The unanswered read isn't a step; nothing but the write and its read-back follows it.
    #expect(await commands(sentTo: SideEffectExample.panel, by: modem) == [
      Command(command1: 0x0D, command2: 0x00),
      Command(command1: 0x20, command2: 0x0A),
      Command(command1: 0x1F, command2: 0x00)
    ])

  }

  @Test func skipsASettingTheDeviceDidntReportBeforeTheWrite() async throws {

    let modem: InMemoryModem = await panelModem(flags: 0x00)
    await modem.setOperatingFlagSideEffect(of: 0x0A, bit: 0x04, isSet: true, of: SideEffectExample.panel)
    await modem.setOperatingFlagSideEffect(of: 0x0A, bit: 0x01, isSet: true, of: SideEffectExample.panel)
    let driftReads = Count()

    // The first request for the drift bit goes unanswered.
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      guard case let .standardRequest(message) = operation, message.command == Command(command1: 0x1F, command2: 0x01) else {

        return

      }

      driftReads.increment()

      if driftReads.value == 1 {

        throw ModemError.deviceTimedOut(message.destination)

      }

    }

    let change: DeviceSettingChange = try await network(modem).device(SideEffectExample.panel).writeSetting("hum", to: "on")

    #expect(change.after == "on")
    #expect(changes(change) == [["sparkle", "-", "off", "on"]])
    #expect(change.unreadSettings.isEmpty)

  }

  // MARK: - A write that isn't confirmed

  @Test func readsNothingAgainWhenTheWriteIsntConfirmed() async throws {

    let modem: InMemoryModem = await panelModem(flags: 0x00)
    await failReads(of: modem, skipping: 0, with: ModemError.deviceTimedOut(SideEffectExample.panel))

    let change: DeviceSettingChange = try await network(modem).device(SideEffectExample.panel).writeSetting("hum", to: "on")

    #expect(change.isConfirmed == false)
    #expect(change.otherSettings == DeviceSettingChange.OtherSettings(outcome: .notConfirmed))
    #expect(await commands(sentTo: SideEffectExample.panel, by: modem) == [
      Command(command1: 0x1F, command2: 0x00),
      Command(command1: 0x1F, command2: 0x01),
      Command(command1: 0x0D, command2: 0x00),
      Command(command1: 0x20, command2: 0x0A)
    ])

  }

  @Test func readsNothingAgainWhenTheDeviceReportsAnotherValue() async throws {

    let modem = SettingsModem(device: SideEffectExample.lamp, flags: 0x00, values: [7: 0x00, 8: 0x10, 9: 0xA2])
    await modem.ignoreWrites()
    let lamp: Device = network(modem).device(SideEffectExample.lamp)

    await #expect(throws: DeviceSettingError.self) {

      _ = try await lamp.writeSetting("lingerTime", to: "0x05")

    }

    #expect(await modem.sent == ["2E 00 01 00 00", "1F 00", "2E 00 01 05 05", "2E 00 01 00 00"])

  }

  // MARK: - A re-read that fails

  @Test func namesTheSettingsThatWentUnreadAfterTheWrite() async throws {

    let modem: InMemoryModem = await panelModem(flags: 0x00)
    await modem.setOperatingFlagSideEffect(of: 0x0A, bit: 0x04, isSet: true, of: SideEffectExample.panel)
    await failReads(of: modem, query: 0x01, skipping: 0, with: ModemError.deviceTimedOut(SideEffectExample.panel))

    let change: DeviceSettingChange = try await network(modem).device(SideEffectExample.panel).writeSetting("hum", to: "on")

    #expect(change.otherSettings.outcome == .compared)
    #expect(changes(change) == [["sparkle", "-", "off", "on"]])
    #expect(change.unreadSettings.map(\.title) == ["Drift"])

  }

  @Test func keepsTheWriteWhenTheConnectionClosesAsTheOtherSettingsAreReadAgain() async throws {

    let modem: InMemoryModem = await panelModem(flags: 0x00)
    await modem.setOperatingFlagSideEffect(of: 0x0A, bit: 0x04, isSet: true, of: SideEffectExample.panel)
    await failReads(of: modem, skipping: 1, with: ModemError.connectionClosed)

    let change: DeviceSettingChange = try await network(modem).device(SideEffectExample.panel).writeSetting("hum", to: "on")

    #expect(change.after == "on")
    #expect(change.isConfirmed)
    #expect(change.otherSettings == .notReread(.connectionClosed))
    #expect(change.changedSettings.isEmpty)
    #expect(await modem.operatingFlags[SideEffectExample.panel] == 0x06)

  }

  @Test func saysTheOtherSettingsWerentAnsweredWhenTheDeviceAnswersNoneOfThemAgain() async throws {

    let modem: InMemoryModem = await panelModem(flags: 0x00)
    await modem.setOperatingFlagCommand(0x06, bit: 0x01, isSet: true, of: SideEffectExample.panel)
    // The drift's read-back is request 0x01; the hum and sparkle are read again with 0x00.
    await failReads(of: modem, query: 0x00, skipping: 0, with: ModemError.deviceTimedOut(SideEffectExample.panel))

    let change: DeviceSettingChange = try await network(modem).device(SideEffectExample.panel).writeSetting("drift", to: "on")

    #expect(change.after == "on")
    #expect(change.otherSettings == .notReread(.notAnswered))

  }

  @Test func keepsTheWriteAndTheTasksCancellationWhenItsCanceledAsTheOtherSettingsAreReadAgain() async throws {

    let modem: InMemoryModem = await panelModem(flags: 0x00)
    let network: DeviceNetwork = self.network(modem)
    let written = Count()

    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      guard case let .standardRequest(message) = operation else {

        return

      }

      if message.command.command1 == 0x20 {

        written.increment()

      } else if message.command == Command(command1: 0x1F, command2: 0x01), written.value > 0 {

        // Cancels the task that asked, so the modem throws CancellationError.
        withUnsafeCurrentTask { (task: UnsafeCurrentTask?) -> Void in task?.cancel() }

      }

    }

    let task = Task { () async throws -> (DeviceSettingChange, Bool) in

      let change: DeviceSettingChange = try await network.device(SideEffectExample.panel).writeSetting("hum", to: "on")

      return (change, Task.isCancelled)

    }
    let (change, isCanceled): (DeviceSettingChange, Bool) = try await task.value

    #expect(change.isConfirmed)
    #expect(change.otherSettings == .notReread(.canceled))
    #expect(isCanceled)

  }

}
