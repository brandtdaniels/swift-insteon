import InsteonCore
import InsteonDeviceCatalog
import InsteonHubClient
import InsteonModem
import InsteonProtocol

/// The network of one connection, as the service reaches it: what it knows, how its devices are
/// operated, and what changes on it.
///
/// A modem's `DeviceNetwork` and a Hub Pro's `HubProNetwork` both serve this way, so the
/// service's gate, cache, events and reconnection are the same for either.
public protocol ServedNetwork: Sendable {

  /// What the network knows, to save.
  func snapshot() async -> NetworkSnapshot

  /// The device at an address, if its identity is recorded.
  func registeredDevice(_ address: InsteonAddress) async -> RegisteredDevice?

  /// The catalog devices are described with.
  func catalog() async -> DeviceCatalog?

  /// The operations of a device. Creating them sends nothing.
  func operations(of address: InsteonAddress) -> any DeviceOperating

  /// Asks a device for its identity and records it.
  func identifyDevice(_ address: InsteonAddress) async throws

  /// The modem's address and the identity it reported, or `nil` when neither is known. It sends
  /// nothing.
  func modemIdentity() async -> (address: InsteonAddress, identity: ReportedIdentity?)?
  /// Makes the reads a connection starts with, so a connection that can't be used fails here.
  func prepare() async throws

  /// Subscribes to what changes on the network. The sequence ends with the error that ends the
  /// connection, if one does.
  func changes() async throws -> NetworkChanges

  /// Reads the ALL-Link databases of the modem and of each device the network knows, and keeps
  /// them in what ``snapshot()`` returns. It only reads. A device that doesn't answer stays
  /// unread and doesn't fail the refresh.
  ///
  /// - Returns: Why each device left unread was left unread.
  ///
  /// - Throws: ``ServiceControlError/databasesUnavailable`` for a network that doesn't give out
  ///   its databases, `CancellationError` when canceled, and the modem's error when the
  ///   connection is lost.
  func refreshDatabases() async throws -> [InsteonAddress: BackupUnreadableReason]

  /// The local time the Hub reported when the connection opened, as it wrote it, or `nil` for a
  /// connection that doesn't report one. Reading it changes nothing on the Hub.
  func reportedLocalTime() async -> String?

}

extension ServedNetwork {

  func reportedLocalTime() async -> String? { nil }

}

extension ServedNetwork {
  /// A network that doesn't know its modem's address.
  public func modemIdentity() async -> (address: InsteonAddress, identity: ReportedIdentity?)? { nil }
}

/// What changes on a network, as the connection delivers it.
public enum NetworkChanges: Sendable {

  /// Events the modem hears, which end when the connection does.
  case heard(AsyncStream<DeviceMonitorEvent>)

  /// Events from polling, which end with the error of a poll that fails.
  case polled(AsyncThrowingStream<DeviceMonitorEvent, any Error>)

}

/// A modem's network, served.
struct ModemServedNetwork: ServedNetwork {

  let network: DeviceNetwork

  func snapshot() async -> NetworkSnapshot { await network.snapshot() }

  func registeredDevice(_ address: InsteonAddress) async -> RegisteredDevice? { await network.registry.device(address) }

  func catalog() async -> DeviceCatalog? { await network.registry.catalog }

  func operations(of address: InsteonAddress) -> any DeviceOperating { ModemDeviceOperations(network.device(address)) }

  func identifyDevice(_ address: InsteonAddress) async throws { _ = try await network.identify(address) }

  func modemIdentity() async -> (address: InsteonAddress, identity: ReportedIdentity?)? {
    if let info = await network.knownModemInfo {
      return (info.address, ReportedIdentity(category: info.category, subcategory: info.subcategory, firmwareVersion: info.firmwareVersion))
    }
    return await network.hubLocation?.insteonID.map { ($0, nil) }
  }
  func prepare() async throws {
    _ = try await network.modemInfo()
    _ = try await network.modemDatabase()
  }

  func changes() async throws -> NetworkChanges { .heard(await network.monitor.changes()) }

  func refreshDatabases() async throws -> [InsteonAddress: BackupUnreadableReason] {
    let info = try await network.modemInfo()
    let entries = try await network.modemDatabase()
    // The devices a cached backup lists: the ones the registry and the device states know, and the
    // ones the modem's records name, except the modem.
    let snapshot = await network.snapshot()
    var addresses = Set(snapshot.registry.identities.keys).union(snapshot.devices.keys)
    for entry in entries where entry.record.isInUse { addresses.insert(entry.record.address) }
    addresses.remove(info.address)
    var unread: [InsteonAddress: BackupUnreadableReason] = [:]
    for address in addresses.sorted(by: { $0.bytes.lexicographicallyPrecedes($1.bytes) }) {
      try Task.checkCancellation()
      unread[address] = try await readDatabase(of: address)
    }
    return unread
  }

  /// Reads one device's database, again once if it arrives damaged. A device that doesn't answer,
  /// turns the modem away, whose request the modem refuses or doesn't echo, or whose database
  /// arrives damaged twice (the cache keeps no damaged copy) is left unread. Only cancellation
  /// and a lost connection end the refresh. Each device is asked once, so a device that doesn't
  /// answer costs the modem's own time out once.
  ///
  /// - Returns: Why the device was left unread, or `nil` when it was read.
  private func readDatabase(of address: InsteonAddress) async throws -> BackupUnreadableReason? {
    do {
      var database = try await network.allLinkDatabase(of: address)
      if !database.hasIntactChecksums {
        // A damaged reading isn't kept, so asking again reads the device again.
        database = try await network.allLinkDatabase(of: address)
      }
      return database.hasIntactChecksums ? nil : .damagedRecords
    } catch is CancellationError {
      throw CancellationError()
    } catch ModemError.connectionClosed {
      throw ModemError.connectionClosed
    } catch ModemError.deviceTimedOut, ModemError.timedOut {
      return .noAnswer
    } catch ModemError.deviceRejected {
      return .rejectedModem
    } catch is ModemError {
      return .failed
    } catch is ModemStoppedEchoing {
      // The modem is reachable but still busy with a device that doesn't answer.
      return .modemStoppedEchoing
    } catch is HubStoppedAnswering {
      // The same, as the Hub reports it: it answered before and then stopped on this device.
      return .hubStoppedAnswering
    }
  }
}

/// A Hub Pro's network, served.
struct HubProServedNetwork: ServedNetwork {

  let network: HubProNetwork

  func snapshot() async -> NetworkSnapshot { await network.snapshot() }

  func registeredDevice(_ address: InsteonAddress) async -> RegisteredDevice? { await network.registry.device(address) }

  func catalog() async -> DeviceCatalog? { await network.registry.catalog }

  func operations(of address: InsteonAddress) -> any DeviceOperating { network.device(address) }

  func identifyDevice(_ address: InsteonAddress) async throws { try await network.identify(address) }

  func modemIdentity() async -> (address: InsteonAddress, identity: ReportedIdentity?)? {
    await network.listing().first(where: \.isModem).map { ($0.address, nil) }
  }
  func prepare() async throws {}

  func changes() async throws -> NetworkChanges { .polled(network.changes()) }

  func refreshDatabases() async throws -> [InsteonAddress: BackupUnreadableReason] { throw ServiceControlError.databasesUnavailable }

  func reportedLocalTime() async -> String? { await network.reportedTime }

}
