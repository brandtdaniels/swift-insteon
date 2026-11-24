import Foundation
import InsteonDeviceCatalog
import InsteonHubPro
import InsteonProtocol

/// The Insteon devices a Hub Pro knows: what they are, what the Hub Pro lists for them, and the
/// level each last reported.
///
/// The network reads the Hub Pro's device list and describes each device it lists, so the
/// ``registry`` holds the identity each reported and the Insteon device catalog describes it.
/// It never adds or removes a device on the Hub Pro: the Hub Pro's device table changes with the
/// SET buttons, and the network follows what the Hub Pro lists.
///
/// ```swift
/// let network = HubProNetwork(transport: HubProTransport(host: "192.168.1.20"), catalog: catalog)
///
/// try await network.open()
///
/// let lamp = network.device(address)
/// _ = try await lamp.turnOn(level: 50)
/// ```
///
/// The Hub Pro sends nothing on its own, so ``changes()`` asks it for every device's level at an
/// interval and reports the devices whose level changed. A change made at a device is seen at
/// the next poll.
public actor HubProNetwork {

  /// The shortest interval between polls: 2 seconds, since the Hub Pro can stop answering under
  /// load.
  public static let minimumPollInterval: Duration = .seconds(2)

  /// The interval between polls when none is given: 5 seconds.
  public static let defaultPollInterval: Duration = .seconds(5)

  /// How many polls pass between reads of the Hub Pro's device list by default.
  public static let defaultListRefreshPolls = 12

  /// The identities devices reported, described with the Insteon device catalog.
  public nonisolated let registry: DeviceRegistry

  private let transport: HubProTransport
  private let clock: any Clock<Duration>
  private let now: @Sendable () -> Date
  private let pollInterval: Duration
  private let listRefreshPolls: Int
  let pollSucceeded: @Sendable () async -> Void
  private var states: [InsteonAddress: NetworkDeviceState]
  private var listed: [HubProListedDevice] = []
  private var descriptions: [InsteonAddress: HubProDescription] = [:]
  private var versions: HubProSettings.Versions?
  private var time: String?

  /// Creates a network.
  ///
  /// - Parameters:
  ///   - transport: How the Hub Pro is reached.
  ///   - catalog: The catalog to describe devices with, or `nil` to describe them by their
  ///     identities alone.
  ///   - snapshot: What the network knew before. Defaults to nothing.
  ///   - pollInterval: How long to wait between polls, at least ``minimumPollInterval``.
  ///     Defaults to ``defaultPollInterval``.
  ///   - clock: The clock that times the polls. Defaults to a `ContinuousClock`.
  ///   - listRefreshPolls: How many polls pass between reads of the device list. Defaults to
  ///     ``defaultListRefreshPolls``.
  ///   - now: The current time, for when a device last answered.
  ///   - onPollSucceeded: Called each time the Hub Pro answers a poll, whether or not a level changed.
  public init(
    transport: HubProTransport,
    catalog: DeviceCatalog?,
    snapshot: NetworkSnapshot = NetworkSnapshot(),
    pollInterval: Duration = HubProNetwork.defaultPollInterval,
    clock: any Clock<Duration> = ContinuousClock(),
    listRefreshPolls: Int = HubProNetwork.defaultListRefreshPolls,
    now: @escaping @Sendable () -> Date = { Date() },
    onPollSucceeded: @escaping @Sendable () async -> Void = {}
  ) {

    self.pollSucceeded = onPollSucceeded
    self.transport = transport
    self.registry = DeviceRegistry(catalog: catalog, snapshot: snapshot.registry)
    self.states = snapshot.devices
    self.pollInterval = max(pollInterval, Self.minimumPollInterval)
    self.clock = clock
    self.listRefreshPolls = max(listRefreshPolls, 1)
    self.now = now

  }

  /// Creates a network that describes devices with a catalog a front end loaded.
  ///
  /// - Parameters:
  ///   - transport: How the Hub Pro is reached.
  ///   - catalog: The catalog to describe devices with, or `nil` to describe them by their
  ///     identities alone.
  ///   - snapshot: What the network knew before. Defaults to nothing.
  ///   - pollInterval: How long to wait between polls, at least ``minimumPollInterval``.
  ///   - clock: The clock that times the polls. Defaults to a `ContinuousClock`.
  ///   - onPollSucceeded: Called each time the Hub Pro answers a poll.
  public init(
    transport: HubProTransport,
    catalog: ProductCatalog?,
    snapshot: NetworkSnapshot = NetworkSnapshot(),
    pollInterval: Duration = HubProNetwork.defaultPollInterval,
    clock: any Clock<Duration> = ContinuousClock(),
    onPollSucceeded: @escaping @Sendable () async -> Void = {}
  ) {

    self.init(transport: transport, catalog: catalog?.catalog, snapshot: snapshot, pollInterval: pollInterval, clock: clock, onPollSucceeded: onPollSucceeded)

  }

  /// Creates a network for the Hub Pro at an address, reached over plain HTTP.
  ///
  /// - Parameters:
  ///   - host: The Hub Pro's host name or IP address.
  ///   - port: The port of its HTTP interface, 80 unless the Hub Pro answers on another.
  ///   - catalog: The catalog to describe devices with, or `nil` to describe them by their
  ///     identities alone.
  ///   - snapshot: What the network knew before. Defaults to nothing.
  public init(host: String, port: Int = 80, catalog: ProductCatalog?, snapshot: NetworkSnapshot = NetworkSnapshot()) {

    self.init(transport: HubProTransport(host: host, port: port), catalog: catalog, snapshot: snapshot)

  }

  // MARK: - What the network knows

  /// Reads the Hub Pro's settings and device list, describes each device, and reads each level.
  ///
  /// - Throws: `HubProError`, or the transport's error, such as `URLError` when the Hub Pro
  ///   doesn't answer.
  public func open() async throws {

    let settings = try await transport.settings()
    versions = settings.version
    time = settings.time

    try await refreshDevices()

    try await readLevels()

  }

  /// Everything the Hub Pro lists, its own modem included, in its order.
  public func listing() -> [HubProListedDevice] {

    listed

  }

  /// The devices the Hub Pro lists, apart from its own modem.
  public func devices() -> [HubProListedDevice] {

    listed.filter { !$0.isModem }

  }

  /// What the Hub Pro reports about a device it lists.
  ///
  /// - Parameter address: The device's address.
  /// - Returns: The description, or `nil` for a device the Hub Pro doesn't list.
  public func description(of address: InsteonAddress) -> HubProDescription? {

    descriptions[address]

  }

  /// The versions of the Hub Pro's software, as it reported them when the network opened.
  public var softwareVersions: HubProSettings.Versions? {

    versions

  }

  /// The time the Hub Pro reported when the network opened, as it wrote it: the home's local time, such as
  /// `11/20/2026 02:38:39 PM`, with no time zone.
  public var reportedTime: String? {

    time

  }

  /// What the network knows, to save and give back to ``init(transport:catalog:snapshot:pollInterval:clock:listRefreshPolls:now:onPollSucceeded:)``.
  public func snapshot() async -> NetworkSnapshot {

    NetworkSnapshot(registry: await registry.snapshot, devices: states, modemDatabase: nil, hub: nil)

  }

  /// A device on the network.
  ///
  /// - Parameter address: The device's address.
  /// - Returns: The device. Creating one sends nothing.
  public nonisolated func device(_ address: InsteonAddress) -> HubProDevice {

    HubProDevice(address: address, network: self)

  }

  /// Reads the Hub Pro's device list again, describes the devices that are new, and forgets the
  /// ones it doesn't list.
  public func refreshDevices() async throws {

    let entries = try await transport.devices()
    let present = Set(entries.filter { !$0.isModem }.map(\.address))

    for address in descriptions.keys where !present.contains(address) {

      descriptions[address] = nil
      states[address] = nil
      await registry.forget(address)

    }

    listed = entries

    for entry in entries where !entry.isModem && descriptions[entry.address] == nil {

      try await describe(entry.address)

    }

  }

  /// Describes a device again, and records the identity it reports.
  ///
  /// - Parameter address: The device's address.
  public func identify(_ address: InsteonAddress) async throws {

    try await describe(address)

  }

  private func describe(_ address: InsteonAddress) async throws {

    let description = try await transport.describe(address)

    descriptions[address] = description

    if let category = description.category, let subcategory = description.subcategory {

      await registry.record(
        ReportedIdentity(category: DeviceCategory(rawValue: category), subcategory: DeviceSubcategory(rawValue: subcategory), firmwareVersion: description.firmwareVersion.map { FirmwareVersion(rawValue: $0) }),
        for: address
      )

    }

  }

  // MARK: - Changes

  /// The devices whose level changes, as the Hub Pro reports it.
  ///
  /// The sequence waits one poll interval, asks the Hub Pro for every level, reports each device
  /// whose level differs from the last one read, and waits again. It reads the device list on
  /// every few polls too. It ends with the error of a poll that fails, so the one that reads it
  /// can reconnect.
  ///
  /// - Returns: A sequence of ``DeviceMonitorEvent/statusChanged(_:)``, for one reader.
  public nonisolated func changes() -> AsyncThrowingStream<DeviceMonitorEvent, any Error> {

    let polling = Polling(network: self, interval: pollInterval, clock: clock, refreshEvery: listRefreshPolls)

    return AsyncThrowingStream { try await polling.next() }

  }

  private actor Polling {

    let network: HubProNetwork
    let interval: Duration
    let clock: any Clock<Duration>
    let refreshEvery: Int
    var pending: [DeviceMonitorEvent] = []
    var polls = 0

    init(network: HubProNetwork, interval: Duration, clock: any Clock<Duration>, refreshEvery: Int) {

      self.network = network
      self.interval = interval
      self.clock = clock
      self.refreshEvery = refreshEvery

    }

    func next() async throws -> DeviceMonitorEvent? {

      while pending.isEmpty {

        try await clock.sleep(for: interval)

        polls += 1

        if polls % refreshEvery == 0 {

          try await network.refreshDevices()

        }

        pending = try await network.readLevels()

        await network.pollSucceeded()

      }

      return pending.removeFirst()

    }

  }

  /// Reads every level, records them, and reports the devices that differ from the last read.
  @discardableResult
  private func readLevels() async throws -> [DeviceMonitorEvent] {

    let levels = try await transport.levels()
    var events: [DeviceMonitorEvent] = []

    for (address, level) in levels.sorted(by: { $0.key.bytes.lexicographicallyPrecedes($1.key.bytes) }) {

      if descriptions[address] == nil, !(listed.first { $0.address == address }?.isModem ?? false) {

        // A device the unit reports but the list hasn't shown yet.
        try await refreshDevices()

      }

      let before = states[address]?.level

      recordAnswer(of: address, level: level)

      if let before, before != level {

        events.append(.statusChanged(address))

      }

    }

    return events

  }

  // MARK: - Used by devices

  func perform(_ command: HubProCommand, on address: InsteonAddress) async throws -> HubProCommandResult {

    try await transport.perform(command, on: address)

  }

  func recordAnswer(of address: InsteonAddress, level: UInt8?) {

    if let level {

      states[address, default: NetworkDeviceState()].level = level

    }

    let seconds = now().timeIntervalSince1970.rounded(.down)

    states[address, default: NetworkDeviceState()].lastSeen = Date(timeIntervalSince1970: seconds)

  }

}
