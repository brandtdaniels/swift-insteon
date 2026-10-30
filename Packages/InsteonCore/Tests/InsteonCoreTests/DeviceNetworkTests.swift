import Foundation
import Testing
@testable import InsteonCore
import InsteonLinking
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Times a test gives a network, one after another, each a minute after the last.
final class FixedTimes: @unchecked Sendable {

  private let lock: NSLock = NSLock()

  private var next: Date

  /// Creates times starting at a fixed date.
  init(startingAt start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {

    self.next = start

  }

  /// The next time.
  func now() -> Date {

    lock.withLock {

      let time: Date = next
      next = next.addingTimeInterval(60)

      return time

    }

  }

}

/// A network on an in-memory modem, on a ``TestClock`` and fixed times.
struct DeviceNetworkTests {

  let clock: TestClock = TestClock()

  let times: FixedTimes = FixedTimes()

  let link = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: InsteonAddress(0x11, 0x22, 0x33), data1: 0xFF, data2: 0x1C, data3: 0x01)

  var plugPressed: SetButtonPressed {

    SetButtonPressed(sender: Example.plug, role: .responder, category: 0x02, subcategory: 0x7A, firmwareVersion: 0x41)

  }

  func network(_ modem: InMemoryModem, snapshot: NetworkSnapshot = NetworkSnapshot(), hub: HubLocation? = nil) -> DeviceNetwork {

    let times: FixedTimes = self.times

    return DeviceNetwork(
      modem: modem,
      catalog: Example.catalog,
      snapshot: snapshot,
      hub: hub,
      clock: clock,
      now: { () -> Date in times.now() }
    )

  }

  // MARK: - Identifying

  @Test func identifiesADeviceAndRecordsItsIdentityEngineAndWhenItAnswered() async throws {

    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: Example.plug)
    await modem.setIdentity(plugPressed)
    let network: DeviceNetwork = self.network(modem)

    let identification: DeviceIdentification = try await network.identify(Example.plug)
    let state: NetworkDeviceState? = await network.state(of: Example.plug)

    #expect(identification.identity == plugPressed)
    #expect(await network.registry.device(Example.plug)?.identity == Example.plugIdentity)
    #expect(state?.engine == .i2cs)
    #expect(state?.lastSeen == Date(timeIntervalSince1970: 1_800_000_000))

  }

  @Test func sharesAnIdentificationInProgressForTheSameAddress() async throws {

    let modem = InMemoryModem()
    let network: DeviceNetwork = self.network(modem)

    // The device sends no broadcast, so each identification waits for its timeout on the
    // test's clock, and stays in progress until the clock is advanced.
    let first = Task { () async throws -> DeviceIdentification in try await network.identify(Example.plug) }

    await clock.waitForSleeper(until: Modem.defaultRequestTimeout)

    let second = Task { () async throws -> DeviceIdentification in try await network.identify(Example.plug) }
    let third = Task { () async throws -> DeviceIdentification in try await network.identify(Example.plug) }

    while await network.joinedIdentifications < 2 {

      await Task.yield()

    }

    clock.advance(by: Modem.defaultRequestTimeout)

    let results: [DeviceIdentification] = [try await first.value, try await second.value, try await third.value]
    let engineRequests: Int = await modem.linkingSteps.filter { (step: InMemoryModem.LinkingStep) -> Bool in

      step == .device(Example.plug, Command(command1: 0x0D), isExtended: false)

    }.count

    #expect(engineRequests == 1)
    #expect(Set(results).count == 1)
    #expect(results.first?.engine == .i2)

  }

  @Test func asksAgainOnceAnIdentificationIsOver() async throws {

    let modem = InMemoryModem()
    await modem.setIdentity(plugPressed)
    let network: DeviceNetwork = self.network(modem)

    _ = try await network.identify(Example.plug)
    _ = try await network.identify(Example.plug)

    let engineRequests: Int = await modem.linkingSteps.count

    #expect(engineRequests == 2)
    #expect(await network.joinedIdentifications == 0)

  }

  @Test func identifiesDifferentAddressesSeparately() async throws {

    let modem = InMemoryModem()
    await modem.setIdentity(plugPressed)
    await modem.setIdentity(SetButtonPressed(sender: Example.lamp, role: .responder, category: 0x01, subcategory: 0x7B, firmwareVersion: nil))
    let network: DeviceNetwork = self.network(modem)

    async let plug: DeviceIdentification = network.identify(Example.plug)
    async let lamp: DeviceIdentification = network.identify(Example.lamp)

    let identifications: [DeviceIdentification] = try await [plug, lamp]

    #expect(identifications.map(\.device) == [Example.plug, Example.lamp])
    #expect(await network.registry.device(Example.lamp)?.identity == Example.lampIdentity)
    #expect(await network.joinedIdentifications == 0)

  }

  @Test func recordsAnI2CSDeviceThatRejectsTheModemWithoutAnIdentity() async throws {

    let modem = InMemoryModem()
    await modem.setUnlinked(Example.plug)
    let network: DeviceNetwork = self.network(modem)

    let identification: DeviceIdentification = try await network.identify(Example.plug)

    #expect(!identification.acceptsModem)
    #expect(await network.registry.device(Example.plug) == nil)
    #expect(await network.state(of: Example.plug)?.engine == .i2cs)

  }

  // MARK: - Device databases

  @Test func servesADatabaseFromTheSnapshotWhileTheDeltaMatches() async throws {

    let modem = InMemoryModem()
    await modem.setDatabase([0x0FFF: link], of: Example.plug)
    await modem.setLevel(0xFF, of: Example.plug)

    let kept = AllLinkDatabaseCopy(delta: 0x00, records: [AllLinkRecordResponse(sender: Example.plug, address: 0x0FFF, record: link)])
    let snapshot = NetworkSnapshot(devices: [Example.plug: NetworkDeviceState(allLinkDatabase: kept)])
    let network: DeviceNetwork = self.network(modem, snapshot: snapshot)

    let database: AllLinkDatabaseCopy = try await network.allLinkDatabase(of: Example.plug)

    #expect(database == kept)
    #expect(await modem.databaseReads[Example.plug] == nil)
    #expect(await network.state(of: Example.plug)?.level == 0xFF)

  }

  @Test func readsADatabaseAgainWhenTheDeltaDiffers() async throws {

    let modem = InMemoryModem()
    await modem.setDatabase([0x0FFF: link], of: Example.plug)
    await modem.changeDatabase(of: Example.plug)

    let stale = AllLinkDatabaseCopy(delta: 0x00, records: [])
    let snapshot = NetworkSnapshot(devices: [Example.plug: NetworkDeviceState(allLinkDatabase: stale)])
    let network: DeviceNetwork = self.network(modem, snapshot: snapshot)

    let database: AllLinkDatabaseCopy = try await network.allLinkDatabase(of: Example.plug)

    #expect(database.delta == 0x01)
    #expect(database.records.first?.record == link)
    #expect(await modem.databaseReads[Example.plug] == 1)
    #expect(await network.snapshot().devices[Example.plug]?.allLinkDatabase == database)

  }

  @Test func readsADatabaseItHasNoCopyOf() async throws {

    let modem = InMemoryModem()
    await modem.setDatabase([0x0FFF: link], of: Example.plug)
    let network: DeviceNetwork = self.network(modem)

    _ = try await network.allLinkDatabase(of: Example.plug)
    _ = try await network.allLinkDatabase(of: Example.plug)

    #expect(await modem.databaseReads[Example.plug] == 1)

  }

  @Test func updatesWhenADeviceWasLastSeenFromItsClock() async throws {

    let modem = InMemoryModem()
    await modem.setLevel(0x80, of: Example.plug)
    let network: DeviceNetwork = self.network(modem)

    _ = try await network.allLinkDatabase(of: Example.plug)

    #expect(await network.state(of: Example.plug)?.lastSeen == Date(timeIntervalSince1970: 1_800_000_000))

    await modem.setLevel(0x00, of: Example.plug)
    _ = try await network.allLinkDatabase(of: Example.plug)

    let state: NetworkDeviceState? = await network.state(of: Example.plug)

    #expect(state?.lastSeen == Date(timeIntervalSince1970: 1_800_000_060))
    #expect(state?.level == 0x00)

  }

  @Test func keepsWhenADeviceWasSeenToTheSecond() async throws {

    let modem = InMemoryModem()
    let network = DeviceNetwork(
      modem: modem,
      catalog: nil,
      clock: clock,
      now: { () -> Date in Date(timeIntervalSince1970: 1_800_000_000.75) }
    )

    _ = try await network.allLinkDatabase(of: Example.plug)

    #expect(await network.state(of: Example.plug)?.lastSeen == Date(timeIntervalSince1970: 1_800_000_000))

  }

  @Test func doesntMarkADeviceThatRejectsTheModemAsSeenByItsDatabase() async throws {

    let modem = InMemoryModem()
    await modem.setUnlinked(Example.plug)
    let network: DeviceNetwork = self.network(modem)

    await #expect(throws: ModemError.self) {

      _ = try await network.allLinkDatabase(of: Example.plug)

    }

    #expect(await network.state(of: Example.plug) == nil)

  }

  // MARK: - The modem's database

  @Test func readsTheModemsDatabaseEveryTimeAndDescribesEachDevice() async throws {

    let modem = InMemoryModem()
    let controls = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xE2), group: 0x00, address: Example.plug, data1: 0x02, data2: 0x7A, data3: 0x41)
    let responds = AllLinkRecord(flags: AllLinkRecordFlags(rawValue: 0xA2), group: 0x01, address: Example.lamp)
    await modem.setModemRecords([controls, responds])

    let snapshot = NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: [Example.plug: Example.plugIdentity]))
    let network: DeviceNetwork = self.network(modem, snapshot: snapshot)

    let entries: [ModemDatabaseEntry] = try await network.modemDatabase()
    _ = try await network.modemDatabase()

    #expect(entries.map(\.record) == [controls, responds])
    #expect(entries.first?.device?.deviceDescription.displayName == "Example Plug 9001")
    #expect(entries.last?.device == nil)
    #expect(await modem.modemDatabaseReads == 2)
    #expect(await network.snapshot().modemDatabase == [controls, responds])

  }

  // MARK: - The Hub

  @Test func keepsTheHubsInsteonIDForTheSameEndpoint() async throws {

    let modem = InMemoryModem()
    let known = HubLocation(host: "192.0.2.10", port: 25105, insteonID: InsteonAddress(0x11, 0x22, 0x33))
    let snapshot = NetworkSnapshot(hub: known)

    #expect(await self.network(modem, snapshot: snapshot, hub: HubLocation(host: "192.0.2.10", port: 25105)).hubLocation == known)
    #expect(await self.network(modem, snapshot: snapshot, hub: nil).hubLocation == known)
    #expect(await self.network(modem, snapshot: snapshot, hub: HubLocation(host: "192.0.2.11", port: 25105)).hubLocation == HubLocation(host: "192.0.2.11", port: 25105))

  }

  @Test func learnsTheHubsInsteonIDFromTheModem() async throws {

    let modem = InMemoryModem()
    let network: DeviceNetwork = self.network(modem, hub: HubLocation(host: "192.0.2.10", port: 25105))

    let info: ModemInfo = try await network.modemInfo()

    #expect(await network.hubLocation?.insteonID == info.address)

  }

  @Test func leavesTheSnapshotsHubAloneForAModemThatIsntAHubs() async throws {

    let modem = InMemoryModem()
    let known = HubLocation(host: "192.0.2.10", port: 25105, insteonID: InsteonAddress(0x44, 0x55, 0x66))
    let unidentified = HubLocation(host: "192.0.2.10", port: 25105)

    // A serial modem, with the Hub the snapshot names.
    let network: DeviceNetwork = self.network(modem, snapshot: NetworkSnapshot(hub: known))
    let other: DeviceNetwork = self.network(modem, snapshot: NetworkSnapshot(hub: unidentified))

    _ = try await network.modemInfo()
    _ = try await other.modemInfo()

    #expect(await network.hubLocation == known)
    #expect(await network.snapshot().hub == known)
    #expect(await other.hubLocation == unidentified)

  }

  @Test func leavesTheHubOutForAModemThatIsntAHubs() async throws {

    let modem = InMemoryModem()
    let network: DeviceNetwork = self.network(modem)

    _ = try await network.modemInfo()

    #expect(await network.hubLocation == nil)
    #expect(await network.snapshot().hub == nil)

  }

  // MARK: - The snapshot

  @Test func givesBackWhatItLearnedAsASnapshotThatRestoresIt() async throws {

    let modem = InMemoryModem()
    await modem.setEngine(.i2cs, of: Example.plug)
    await modem.setIdentity(plugPressed)
    await modem.setDatabase([0x0FFF: link], of: Example.plug)
    await modem.setLevel(0xFF, of: Example.plug)
    await modem.setModemRecords([link])
    let network: DeviceNetwork = self.network(modem, hub: HubLocation(host: "192.0.2.10", port: 25105))

    _ = try await network.identify(Example.plug)
    _ = try await network.allLinkDatabase(of: Example.plug)
    _ = try await network.modemDatabase()
    _ = try await network.modemInfo()

    let snapshot: NetworkSnapshot = await network.snapshot()
    let state: NetworkDeviceState? = snapshot.devices[Example.plug]

    #expect(snapshot.registry.identities == [Example.plug: Example.plugIdentity])
    #expect(state?.engine == .i2cs)
    #expect(state?.level == 0xFF)
    #expect(state?.lastSeen == Date(timeIntervalSince1970: 1_800_000_060))
    #expect(state?.allLinkDatabase?.records.first?.record == link)
    #expect(snapshot.modemDatabase == [link])
    #expect(snapshot.hub == HubLocation(host: "192.0.2.10", port: 25105, insteonID: InsteonAddress(0x11, 0x22, 0x33)))

    let restored: DeviceNetwork = self.network(InMemoryModem(), snapshot: snapshot)

    #expect(await restored.snapshot() == snapshot)

  }

  @Test func leavesOutADatabaseTheCacheForgot() async throws {

    let modem = InMemoryModem()
    let network: DeviceNetwork = self.network(modem)

    _ = try await network.allLinkDatabase(of: Example.plug)
    await network.cache.invalidate(Example.plug)

    let snapshot: NetworkSnapshot = await network.snapshot()

    #expect(snapshot.devices[Example.plug]?.allLinkDatabase == nil)
    #expect(snapshot.devices[Example.plug]?.lastSeen != nil)

  }

}
