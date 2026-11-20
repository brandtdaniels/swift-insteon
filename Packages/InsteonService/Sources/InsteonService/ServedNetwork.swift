import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

/// The network of one connection, as the service reaches it: what it knows, how its devices are
/// operated, and what changes on it.
///
/// A modem's ``DeviceNetwork`` and a Hub Pro's ``HubProNetwork`` both serve this way, so the
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

  /// Makes the reads a connection starts with, so a connection that can't be used fails here.
  func prepare() async throws

  /// Subscribes to what changes on the network. The sequence ends with the error that ends the
  /// connection, if one does.
  func changes() async throws -> NetworkChanges

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

  func prepare() async throws {
    _ = try await network.modemInfo()
    _ = try await network.modemDatabase()
  }

  func changes() async throws -> NetworkChanges { .heard(await network.monitor.changes()) }

}

/// A Hub Pro's network, served.
struct HubProServedNetwork: ServedNetwork {

  let network: HubProNetwork

  func snapshot() async -> NetworkSnapshot { await network.snapshot() }

  func registeredDevice(_ address: InsteonAddress) async -> RegisteredDevice? { await network.registry.device(address) }

  func catalog() async -> DeviceCatalog? { await network.registry.catalog }

  func operations(of address: InsteonAddress) -> any DeviceOperating { network.device(address) }

  func identifyDevice(_ address: InsteonAddress) async throws { try await network.identify(address) }

  func prepare() async throws {}

  func changes() async throws -> NetworkChanges { .polled(network.changes()) }

}
