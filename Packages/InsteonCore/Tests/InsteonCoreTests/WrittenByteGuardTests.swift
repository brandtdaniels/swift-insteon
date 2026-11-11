import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Every message a device is sent is checked byte by byte on the route it writes, whichever
/// setting, command or action built it, with ``CatalogGuardTests``'s made-up catalog changed to
/// reach its guarded flags byte, D7, by other routes.
struct WrittenByteGuardTests {

  let clock: TestClock = TestClock()

  func device(_ modem: SettingsModem, json: String) throws -> Device {

    DeviceNetwork(
      modem: modem,
      catalog: try DeviceCatalog(json: Data(json.utf8)),
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [CatalogGuardTests.address: CatalogGuardTests.identity])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    ).device(CatalogGuardTests.address)

  }

  /// The catalog with a change to its JSON.
  static func json(replacing pairs: [(String, String)]) -> String {

    pairs.reduce(CatalogGuardTests.json) { (json: String, pair: (String, String)) -> String in

      precondition(json.contains(pair.0), "The catalog has no \(pair.0)")

      return json.replacingOccurrences(of: pair.0, with: pair.1)

    }

  }

  @Test(.timeLimit(.minutes(1))) func refusesAControlActionThatSendsAGuardedExtendedSet() async throws {

    // The load's on action names an extended command whose fixed bytes are the configuration
    // write's selector, so it writes D7 with no report of the kept bits.
    let json: String = Self.json(replacing: [
      (#""extendedCommands": ["#, #""extendedCommands": [ { "name": "brighten", "description": "Brightens.", "command1": "0x2E", "command2": "0x00", "fixed": [{ "position": 2, "value": "0x05" }, { "position": 3, "value": "0x00" }], "effect": "configuration", "idempotent": true },"#),
      (#"{ "name": "on", "label": "On", "command": "lightOn" }"#, #"{ "name": "on", "label": "On", "command": "brighten" }"#)
    ])
    let modem = SettingsModem(device: CatalogGuardTests.address, flags: 0x00, values: [7: 0x04])

    await #expect(throws: DeviceControlError.self) {

      _ = try await device(modem, json: json).turnOn()

    }

    #expect(await modem.extendedWrites.isEmpty)
    #expect(await modem.values[7] == 0x04)

  }

  @Test(.timeLimit(.minutes(1))) func refusesAValueWrittenThroughAGuardedSelectorRoute() async throws {

    // A value at D12 with no flags query, written with the configuration's selector at D3,
    // which is D7's route.
    let json: String = Self.json(replacing: [
      (#"{ "name": "sleep", "description": "A sleep setting.", "byte": 9, "write": "sleepNever", "label": "Sleep" }"#,
       #"{ "name": "sleep", "description": "A sleep setting.", "byte": 9, "write": "sleepNever", "label": "Sleep" }, { "name": "decoy", "description": "A decoy.", "byte": 12, "label": "Decoy" }"#),
      (#""bytes": [{ "position": 3, "value": "configuration" }] }"#,
       #""bytes": [{ "position": 3, "value": "configuration" }] }, { "name": "decoyWrite", "description": "Writes the decoy.", "selector": "0x05", "perButton": false, "bytes": [{ "position": 3, "value": "decoy" }] }"#)
    ])
    let modem = SettingsModem(device: CatalogGuardTests.address, flags: 0x00, values: [7: 0x04, 12: 0x00])

    let error: DeviceSettingError? = await #expect(throws: DeviceSettingError.self) {

      _ = try await device(modem, json: json).writeSetting("decoy", to: "0xFF")

    }

    #expect(CatalogGuardTests.lockedLabel(error) == "Beeper lock")
    #expect(await modem.extendedWrites.isEmpty)
    #expect(await modem.values[7] == 0x04)

    // Writing 0x00 through the route would clear the kept extended-only bit the device reports
    // at D7, so it isn't written either.
    let keeps: DeviceSettingError? = await #expect(throws: DeviceSettingError.self) {

      _ = try await device(modem, json: json).writeSetting("decoy", to: "0x00")

    }

    #expect(CatalogGuardTests.neverWrittenLabel(keeps) != nil)
    #expect(await modem.values[7] == 0x04)

  }

  @Test(.timeLimit(.minutes(1))) func refusesAnExtendedSetAsGivenWhoseSelectorTheCommandSetDoesntList() async throws {

    let modem = SettingsModem(device: CatalogGuardTests.address, flags: 0x00, values: [:])
    let network = DeviceNetwork(
      modem: modem,
      catalog: try CatalogGuardTests.catalog(),
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [CatalogGuardTests.address: CatalogGuardTests.identity])),
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000) }
    )
    let unlisted = DirectMessage(to: CatalogGuardTests.address, command1: 0x2E, command2: 0x00, data: [0x01, 0x09, 0xFF], hasChecksum: true)

    await #expect(throws: SendRefusal.unlistedExtendedSet(selector: 0x09)) {

      _ = try await network.send(unlisted, collectingFor: .zero, consent: .everything) { (_: ReceivedFrame) -> Void in }

    }

    #expect(await modem.extendedMessages.isEmpty)

  }

}
