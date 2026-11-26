import Foundation
import InsteonCore
import InsteonService
import Observation

/// What the devices screen shows for one device.
public struct DeviceRow: Identifiable, Equatable, Sendable {
  /// A device's level as a person reads it.
  public enum Level: Equatable, Sendable {
    /// The network has no reading.
    case unknown
    /// The device is off.
    case off
    /// The device is on at this percent.
    case percent(Int)
  }

  /// The device's address, which names the row.
  public let id: InsteonAddress
  /// The product name, or a stand-in until the device is identified.
  public let title: String
  /// The device's address as text.
  public let subtitle: String
  /// Whether the device has an on and off control.
  public let canSwitch: Bool
  /// Whether the device takes a level.
  public let canDim: Bool
  /// The level the screen shows.
  public var level: Level
}

/// The devices screen: what the network lists, and the on and off controls.
///
/// It calls the network and presents the answer. The network decides what a device can do, whether a
/// command may be sent and what a refusal means.
@MainActor
@Observable
public final class DevicesScreen<Network: DeviceQuerying & DeviceCommanding> {
  /// Where the screen's load stands.
  public enum State: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
  }

  /// Where the screen's loading stands: loading while any load is out, otherwise how the last load ended.
  public private(set) var state: State = .idle
  /// The devices, in the order the network lists them. A failed load leaves the previous rows.
  public private(set) var rows: [DeviceRow] = []
  /// The last refusal of a command, for the screen to show once.
  public var notice: String?

  /// Whether a load is out, for the view to show a loading indicator.
  public var isLoading: Bool { state == .loading }

  /// Whether the last load succeeded and the network lists no devices.
  public var isEmpty: Bool { state == .loaded && rows.isEmpty }

  /// What the last load failed with, to show beside any rows kept from before, until a load succeeds.
  public var failure: String? {
    if case let .failed(message) = settled { message } else { nil }
  }

  private var busy: Set<InsteonAddress> = []
  private let network: Network
  private var started = 0
  private var applied = 0
  private var inFlight = 0
  private var settled: State = .idle

  /// Whether a command for the row's device is out, so another tap on it is ignored.
  public func isBusy(_ row: DeviceRow) -> Bool { busy.contains(row.id) }

  /// Creates a screen over a network.
  public init(network: Network) {
    self.network = network
  }

  /// Asks the network for its devices.
  ///
  /// Loads can overlap. A result applies only if no later load has applied one, so a slow older load
  /// never replaces a newer load's rows. A cancelled load changes nothing, and the screen leaves the
  /// loading state once no load is out. A failed load keeps the rows that were shown.
  public func load() async {
    started += 1
    let mine = started
    inFlight += 1
    state = .loading
    defer {
      inFlight -= 1
      if inFlight == 0 { state = settled }
    }
    do {
      let devices = try await network.devices()
      guard mine > applied else { return }
      applied = mine
      rows = devices.map(Self.row)
      settled = .loaded
    } catch is CancellationError {
      return
    } catch {
      guard mine > applied else { return }
      applied = mine
      settled = .failed(Self.message(for: error))
    }
  }

  /// Sends a device an on or off command, then shows the level the device reported.
  ///
  /// An acknowledgment that carries a status shows that status. Any other answer shows the level the
  /// network lists for the device, read again, because the screen can't tell what level the device holds.
  public func turn(_ row: DeviceRow, on: Bool) async {
    // The gate reads the current row, not the caller's copy, which a load can have outdated.
    guard let current = rows.first(where: { $0.id == row.id }), current.canSwitch, !busy.contains(row.id) else { return }
    busy.insert(row.id)
    defer { busy.remove(row.id) }
    notice = nil
    do {
      let receipt = try await network.execute(ServiceCommand(address: row.id, action: on ? .on : .off))
      if receipt.outcome == .acknowledged, let status = receipt.status {
        show(Self.level(of: status.value), for: row.id)
      } else {
        await refresh(row.id)
      }
    } catch is CancellationError {
      return
    } catch {
      notice = Self.message(for: error)
    }
  }

  /// Reads the network's list again and updates one device's level, leaving the other rows as they are.
  private func refresh(_ id: InsteonAddress) async {
    do {
      guard let device = try await network.devices().first(where: { $0.address == id }) else { return show(.unknown, for: id) }
      show(Self.row(device).level, for: id)
    } catch is CancellationError {
      return
    } catch {
      show(.unknown, for: id)
      notice = "The level couldn't be read after the command."
    }
  }

  /// A load can reorder or drop rows while a command is out, so a row is found by its device each time.
  private func show(_ level: DeviceRow.Level, for id: InsteonAddress) {
    if let index = rows.firstIndex(where: { $0.id == id }) { rows[index].level = level }
  }

  private static func level(of value: UInt8?) -> DeviceRow.Level {
    switch value {
    case nil: .unknown
    case 0?: .off
    // Only 0 is off, so a level that rounds to 0% still shows as on, at the least a percent can say.
    case let value?: .percent(max(1, Int((Double(value) * 100 / 255).rounded())))
    }
  }

  private static func row(_ device: ServiceDevice) -> DeviceRow {
    DeviceRow(
      id: device.address, title: device.productName ?? "Unidentified device", subtitle: device.address.description,
      canSwitch: device.canTurnOnAndOff, canDim: device.canDim, level: level(of: device.value))
  }

  private static func message(for error: any Error) -> String {
    if let message = InsteonErrorDescription.message(for: error) { return message }
    switch error as? ServiceControlError {
    case .busy?: return "The service is busy with another request. Try again."
    case .modemUnavailable?: return "The service can't reach its modem right now."
    case .notLinked?: return "That device isn't linked to the modem."
    case .notIdentified?: return "That device hasn't said what it is yet."
    case .unsupportedControl?: return "That device has no on and off control."
    case .invalidLevel?: return "That level isn't one the device can take."
    case .unknownDevice?: return "The service doesn't know that device."
    case .databasesUnavailable?: return "This network doesn't give out its link databases."
    case nil: return "The service couldn't be reached."
    }
  }
}
