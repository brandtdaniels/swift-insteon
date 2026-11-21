import Foundation
import InsteonDeviceCatalog
import InsteonHubPro
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol
import InsteonTestSupport
import Testing
@testable import InsteonCore

/// A line a reader reports, as the front end sees it.
final class ProgressLog: @unchecked Sendable {

  private let lock: NSLock = NSLock()
  private var items: [BackupProgress] = []

  var all: [BackupProgress] { lock.withLock { items } }

  func add(_ item: BackupProgress) { lock.withLock { items.append(item) } }

}

/// Reading a modem and its devices into a backup, with every request a read.
@Suite(.timeLimit(.minutes(1)))
struct HomeBackupReaderTests {

  static let lamp = BackupExample.lamp
  static let plug = BackupExample.plug
  static let sensor = BackupExample.sensor

  static let responder: AllLinkRecordFlags = [.inUse, .usedBefore]
  static let controller: AllLinkRecordFlags = [.inUse, .usedBefore, .controller]

  /// The old modem controls group 1 of each device, and each device responds to it.
  static func fixture(devices: [InsteonAddress] = [lamp, plug]) async -> InMemoryModem {

    let modem = InMemoryModem()
    let modemAddress: InsteonAddress = BackupExample.oldModem

    await modem.setModemRecords(devices.map { AllLinkRecord(flags: controller, group: 1, address: $0, data1: 0x01, data2: 0x02, data3: 0x03) })

    for device in devices {

      await modem.setDatabase([0x0FFF: AllLinkRecord(flags: responder, group: 1, address: modemAddress, data1: 0xFF, data2: 0x1F, data3: 0x01)], of: device)
      await modem.setEngine(.i2, of: device)

    }

    return modem

  }

  /// A network that already knows each device's identity, so reading sends no ID Request.
  func network(_ modem: any LinkingModem, known: [InsteonAddress] = [lamp, plug]) -> DeviceNetwork {

    var identities: [InsteonAddress: ReportedIdentity] = [:]
    var states: [InsteonAddress: NetworkDeviceState] = [:]

    for device in known {

      identities[device] = ReportedIdentity(category: 0x01, subcategory: 0x02, firmwareVersion: 0x41)
      states[device] = NetworkDeviceState(engine: .i2)

    }

    return DeviceNetwork(
      modem: modem,
      catalog: nil,
      snapshot: NetworkSnapshot(registry: DeviceRegistrySnapshot(identities: identities), devices: states),
      clock: TestClock()
    )

  }

  // MARK: - Reading the modem and its devices

  @Test func readsTheModemsIdentityAndDatabase() async throws {

    let modem = await Self.fixture()
    let backup: HomeBackup = try await HomeBackupReader.read(network: network(modem), createdAt: BackupExample.createdAt)

    #expect(backup.source == .modem)
    #expect(backup.modem?.address == BackupExample.oldModem)
    #expect(await modem.address == BackupExample.oldModem)
    #expect(backup.modem?.identity == BackupIdentity(category: 0x03, subcategory: 0x15, firmwareVersion: 0x9E))
    #expect(backup.modem?.allLinkDatabase?.map(\.address) == [Self.lamp, Self.plug])
    #expect(backup.modem?.allLinkDatabase?.first?.role == .controller)
    #expect(backup.modem?.allLinkDatabase?.first?.data == [0x01, 0x02, 0x03])

  }

  @Test func readsEachDevicesDatabaseWithItsEndAndEngine() async throws {

    let modem = await Self.fixture()
    let backup: HomeBackup = try await HomeBackupReader.read(network: network(modem), createdAt: BackupExample.createdAt)
    let lamp = try #require(backup.devices.first { $0.address == Self.lamp })
    let database = try #require(lamp.allLinkDatabase)

    #expect(backup.devices.map(\.address) == [Self.lamp, Self.plug])
    #expect(lamp.engine == .i2)
    #expect(lamp.identity == BackupIdentity(category: 0x01, subcategory: 0x02, firmwareVersion: 0x41))
    #expect(database.isComplete)
    #expect(database.records.first == BackupRecord(state: .inUse, role: .responder, group: 1, address: BackupExample.oldModem, data: [0xFF, 0x1F, 0x01], memoryAddress: 0x0FFF))
    #expect(database.records.last?.state == .end)

  }

  @Test func readsADeviceTheModemNamesEvenWhenTheRegistryDoesNotKnowIt() async throws {

    let modem = await Self.fixture(devices: [Self.lamp])

    await modem.setIdentity(SetButtonPressed(sender: Self.lamp, role: .responder, category: 0x01, subcategory: 0x02, firmwareVersion: 0x41))

    let backup: HomeBackup = try await HomeBackupReader.read(network: network(modem, known: []), createdAt: BackupExample.createdAt)

    #expect(backup.devices.map(\.address) == [Self.lamp])
    #expect(backup.devices.first?.identity == BackupIdentity(category: 0x01, subcategory: 0x02, firmwareVersion: 0x41))
    #expect(backup.devices.first?.allLinkDatabase != nil)

  }

  @Test func leavesTheModemItselfOutOfTheDevices() async throws {

    let modem = await Self.fixture()
    let net: DeviceNetwork = network(modem, known: [Self.lamp, Self.plug, BackupExample.oldModem])
    let backup: HomeBackup = try await HomeBackupReader.read(network: net, createdAt: BackupExample.createdAt)

    #expect(!backup.devices.map(\.address).contains(BackupExample.oldModem))

  }

  @Test func reportsProgressBeforeEachStep() async throws {

    let modem = await Self.fixture()
    let log = ProgressLog()

    _ = try await HomeBackupReader.read(network: network(modem), createdAt: BackupExample.createdAt) { log.add($0) }

    #expect(log.all == [.readingModem, .readingDevice(Self.lamp, position: 1, total: 2), .readingDevice(Self.plug, position: 2, total: 2)])

  }

  // MARK: - Devices that can't be read

  @Test func recordsADeviceThatDoesNotAnswerAndReadsTheRest() async throws {

    let modem = await Self.fixture(devices: [Self.lamp, Self.plug, Self.sensor])

    await modem.setUnanswering(Self.plug)

    let log = ProgressLog()
    let backup: HomeBackup = try await HomeBackupReader.read(network: network(modem, known: [Self.lamp, Self.plug, Self.sensor]), createdAt: BackupExample.createdAt) { log.add($0) }
    let byAddress: [InsteonAddress: BackupDevice] = Dictionary(uniqueKeysWithValues: backup.devices.map { ($0.address, $0) })

    #expect(byAddress[Self.plug]?.unreadable?.reason == .noAnswer)
    #expect(byAddress[Self.plug]?.allLinkDatabase == nil)
    #expect(byAddress[Self.lamp]?.allLinkDatabase != nil)
    #expect(byAddress[Self.sensor]?.allLinkDatabase != nil)
    #expect(log.all.contains(.deviceUnreadable(Self.plug, BackupUnreadable(reason: .noAnswer))))

  }

  @Test func recordsADeviceThatRejectsTheModem() async throws {

    let modem = await Self.fixture()

    await modem.setUnlinked(Self.plug)

    let backup: HomeBackup = try await HomeBackupReader.read(network: network(modem), createdAt: BackupExample.createdAt)

    #expect(backup.devices.first { $0.address == Self.plug }?.unreadable?.reason == .rejectedModem)

  }

  @Test func recordsADeviceWhoseRecordsStayDamagedAfterASecondReading() async throws {

    let modem = await Self.fixture()

    await modem.setDamaged(true, record: 0x0FFF, of: Self.plug)

    let backup: HomeBackup = try await HomeBackupReader.read(network: network(modem), createdAt: BackupExample.createdAt)
    let plug = try #require(backup.devices.first { $0.address == Self.plug })

    #expect(plug.unreadable?.reason == .damagedRecords)
    #expect(plug.unreadable?.detail == "1 of 2 records failed their checksum")
    #expect(await modem.databaseReads[Self.plug] == 2)

  }

  @Test func readsADeviceWhoseRecordWasDamagedOnlyOnce() async throws {

    let modem = await Self.fixture()

    await modem.setDamaged(true, record: 0x0FFF, of: Self.plug)
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .standardRequest(message) = operation, message.destination == Self.plug {

        await modem.setDamaged(false, record: 0x0FFF, of: Self.plug)

      }

    }

    let backup: HomeBackup = try await HomeBackupReader.read(network: network(modem), createdAt: BackupExample.createdAt)

    #expect(backup.devices.first { $0.address == Self.plug }?.allLinkDatabase != nil)

  }

  @Test func stopsWhenTheModemGoesAway() async throws {

    let modem = await Self.fixture()

    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .standardRequest(message) = operation, message.destination == Self.plug {

        throw ModemError.connectionClosed

      }

    }

    await #expect(throws: ModemError.connectionClosed) {

      _ = try await HomeBackupReader.read(network: network(modem), createdAt: BackupExample.createdAt)

    }

  }

  // MARK: - An interrupted backup

  @Test func throwsCancellationAndReturnsNothingWhenInterruptedWhileReadingADevice() async throws {

    let modem = await Self.fixture()

    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      if case let .standardRequest(message) = operation, message.destination == Self.plug {

        throw CancellationError()

      }

    }

    await #expect(throws: CancellationError.self) {

      _ = try await HomeBackupReader.read(network: network(modem), createdAt: BackupExample.createdAt)

    }

  }

  @Test func readsNoDeviceAfterBeingCanceled() async throws {

    let modem = await Self.fixture()
    let task = Task { () async throws -> HomeBackup in

      withUnsafeCurrentTask { $0?.cancel() }

      return try await HomeBackupReader.read(network: network(modem), createdAt: BackupExample.createdAt)

    }

    await #expect(throws: CancellationError.self) { _ = try await task.value }
    #expect(await modem.databaseReads.isEmpty)

  }

  // MARK: - Reads only

  @Test func sendsNothingThatChangesAModemOrADevice() async throws {

    let modem = await Self.fixture(devices: [Self.lamp, Self.plug, Self.sensor])
    let writes = WriteWatch()

    await modem.setUnanswering(Self.sensor)
    await modem.setBeforeOperation { (operation: InMemoryModem.Operation) async throws -> Void in

      switch operation {
      case .readModemDatabase:
        break
      case let .standardRequest(message):
        // Light Status Request and ID Request's engine query ask; anything else would change something.
        if ![0x19, 0x0D, 0x10].contains(message.command.command1) { writes.add("standard \(message.command.command1)") }
      case .send, .extendedRequest:
        writes.add("\(operation)")
      }

    }

    let recording = RecordingModem(modem)
    let net: DeviceNetwork = network(recording, known: [Self.lamp, Self.plug, Self.sensor])

    _ = try await HomeBackupReader.read(network: net, createdAt: BackupExample.createdAt)

    #expect(writes.all == [])
    #expect(await modem.writes.isEmpty)
    #expect(await modem.modemDeletions == 0)

    for call in await recording.calls {

      switch call {
      case .modemInfo, .readModemDatabase, .readAllLinkDatabase:
        break
      case let .standardRequest(message, timeout: _):
        #expect([0x19, 0x0D, 0x10].contains(message.command.command1), "A request that isn't a read: \(call)")
      case .send, .extendedRequest, .readAllLinkRecord, .readModemRecords:
        Issue.record("A call that isn't one of the reads: \(call)")
      }

    }

  }

  // MARK: - A Hub Pro

  @Test func readsAHubProsListAndSaysItGivesNoDatabases() async throws {

    let http = HubProNetworkTests.unit()
    let network = HubProNetwork(transport: HubProTransport(host: HubProUnit.host, httpClient: http), catalog: ControlExample.catalog, clock: TestClock(), now: { Date(timeIntervalSince1970: 1_000) })
    let backup: HomeBackup = try await HomeBackupReader.read(hubPro: network, createdAt: BackupExample.createdAt)

    #expect(backup.source == .hubPro)
    #expect(backup.modem?.address == InsteonAddress(0xAA, 0xBB, 0xCC))
    #expect(backup.modem?.unreadable?.reason == .unavailableFromSource)
    #expect(backup.devices.map(\.address) == [HubProNetworkTests.dimmer])
    #expect(backup.devices.first?.name == "Example Dimmer")
    #expect(backup.devices.first?.type == "Example Dimmer")
    #expect(backup.devices.first?.identity == BackupIdentity(ControlExample.dimmerIdentity))
    #expect(backup.devices.first?.unreadable?.reason == .unavailableFromSource)

  }

  @Test func asksAHubProOnlyForReads() async throws {

    let http = HubProNetworkTests.unit()
    let network = HubProNetwork(transport: HubProTransport(host: HubProUnit.host, httpClient: http), catalog: ControlExample.catalog, clock: TestClock(), now: { Date(timeIntervalSince1970: 1_000) })

    _ = try await HomeBackupReader.read(hubPro: network, createdAt: BackupExample.createdAt)

    for request in await http.sent {

      #expect(request.hasPrefix("GET "), "A request that isn't a read: \(request)")
      #expect(!request.contains("/add") && !request.contains("/remove") && !request.contains("/update"), "A request to a path that changes the Hub Pro: \(request)")

    }

  }

  // MARK: - From what a service cached

  @Test func buildsABackupFromASnapshotWithoutSendingAnything() async throws {

    var snapshot: NetworkSnapshot = NetworkSnapshot()

    snapshot.registry.identities[Self.lamp] = ReportedIdentity(category: 0x01, subcategory: 0x02, firmwareVersion: 0x41)
    snapshot.registry.identities[Self.plug] = ReportedIdentity(category: 0x01, subcategory: 0x02, firmwareVersion: 0x41)
    snapshot.modemDatabase = [AllLinkRecord(flags: Self.controller, group: 1, address: Self.lamp, data1: 0x01, data2: 0x02, data3: 0x03)]
    snapshot.devices[Self.lamp] = NetworkDeviceState(
      engine: .i2,
      allLinkDatabase: AllLinkDatabaseCopy(delta: 0x05, records: [
        AllLinkRecordResponse(sender: Self.lamp, address: 0x0FFF, record: AllLinkRecord(flags: Self.responder, group: 1, address: BackupExample.oldModem, data1: 0xFF, data2: 0x1F, data3: 0x01), hasIntactChecksum: true),
        AllLinkRecordResponse(sender: Self.lamp, address: 0x0FF7, record: AllLinkRecord(flags: [], group: 0, address: InsteonAddress(0, 0, 0)), hasIntactChecksum: true)
      ])
    )

    let backup: HomeBackup = await HomeBackupReader.backup(from: snapshot, modem: (BackupExample.oldModem, ReportedIdentity(category: 0x03, subcategory: 0x15, firmwareVersion: 0x9E)), catalog: nil, createdAt: BackupExample.createdAt)
    let byAddress: [InsteonAddress: BackupDevice] = Dictionary(uniqueKeysWithValues: backup.devices.map { ($0.address, $0) })

    #expect(backup.source == .service)
    #expect(backup.modem?.address == BackupExample.oldModem)
    #expect(backup.modem?.allLinkDatabase?.count == 1)
    #expect(byAddress[Self.lamp]?.allLinkDatabase?.isComplete == true)
    #expect(byAddress[Self.lamp]?.engine == .i2)
    #expect(byAddress[Self.plug]?.unreadable?.reason == .notCached)
    #expect(backup.modem?.identity == BackupIdentity(category: 0x03, subcategory: 0x15, firmwareVersion: 0x9E))

  }

  @Test func marksTheModemsDatabaseNotCachedWhenTheSnapshotHoldsNone() async throws {

    let backup: HomeBackup = await HomeBackupReader.backup(from: NetworkSnapshot(), modem: (BackupExample.oldModem, nil), catalog: nil, createdAt: BackupExample.createdAt)

    #expect(backup.modem?.unreadable?.reason == .notCached)
    #expect(backup.modem?.allLinkDatabase == nil)

  }

  @Test func holdsNoModemWhenItsAddressIsNotKnown() async throws {

    let backup: HomeBackup = await HomeBackupReader.backup(from: NetworkSnapshot(), modem: nil, catalog: nil, createdAt: BackupExample.createdAt)

    #expect(backup.modem == nil)

  }

  @Test func remembersWhatTheModemReportedAboutItself() async throws {

    let modem = await Self.fixture()
    let net: DeviceNetwork = network(modem)

    #expect(await net.knownModemInfo == nil)

    let info: ModemInfo = try await net.modemInfo()

    #expect(await net.knownModemInfo == info)

  }

  @Test func holdsNoCredentialOrHubAddressFromAServiceSnapshot() async throws {

    var snapshot: NetworkSnapshot = NetworkSnapshot(hub: HubLocation(host: "hub.example.invalid", port: 25105, insteonID: BackupExample.oldModem))

    snapshot.registry.identities[BackupExample.lamp] = ReportedIdentity(category: 0x01, subcategory: 0x02, firmwareVersion: 0x41)

    let backup: HomeBackup = await HomeBackupReader.backup(from: snapshot, modem: (BackupExample.oldModem, nil), catalog: nil, createdAt: BackupExample.createdAt)
    let text: String = String(decoding: try backup.encoded(), as: UTF8.self).lowercased()

    for forbidden in ["password", "token", "secret", "hub.example.invalid", "25105", "authorization"] {

      #expect(!text.contains(forbidden), "The backup mentions \(forbidden).")

    }

  }

}

/// What a test saw sent that it didn't expect.
final class WriteWatch: @unchecked Sendable {

  private let lock: NSLock = NSLock()
  private var items: [String] = []

  var all: [String] { lock.withLock { items } }

  func add(_ item: String) { lock.withLock { items.append(item) } }

}
