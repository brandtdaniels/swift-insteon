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

  /// The loading state.
  public private(set) var state: State = .idle
  /// The devices, in the order the network lists them.
  public private(set) var rows: [DeviceRow] = []
  /// The last refusal of a command, for the screen to show once.
  public var notice: String?

  private var busy: Set<InsteonAddress> = []
  private let network: Network

  /// Whether a command for the row's device is out, so another tap on it is ignored.
  public func isBusy(_ row: DeviceRow) -> Bool { busy.contains(row.id) }

  /// Creates a screen over a network.
  public init(network: Network) {
    self.network = network
  }

  /// Asks the network for its devices.
  ///
  /// A load that is cancelled, such as when the view goes away, leaves the rows and the state as they were.
  public func load() async {
    let before = state
    state = .loading
    do {
      rows = try await network.devices().map(Self.row)
      state = .loaded
    } catch is CancellationError {
      state = before
    } catch {
      rows = []
      state = .failed(Self.message(for: error))
    }
  }

  /// Sends a device an on or off command, then shows the level the device reported.
  ///
  /// An acknowledgment that carries a status shows that status. Any other answer shows the level the
  /// network lists for the device, read again, because the screen can't tell what the device now holds.
  public func turn(_ row: DeviceRow, on: Bool) async {
    guard row.canSwitch, rows.contains(where: { $0.id == row.id }), !busy.contains(row.id) else { return }
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
    } catch {
      notice = Self.message(for: error)
    }
  }

  /// Reads the network's list again and updates one device's level, leaving the other rows as they are.
  private func refresh(_ id: InsteonAddress) async {
    do {
      guard let device = try await network.devices().first(where: { $0.address == id }) else { return show(.unknown, for: id) }
      show(Self.row(device).level, for: id)
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
    case nil: return "The service couldn't be reached."
    }
  }
}
