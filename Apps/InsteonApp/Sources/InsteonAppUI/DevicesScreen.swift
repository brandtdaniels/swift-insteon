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

  private let network: Network

  /// Creates a screen over a network.
  public init(network: Network) {
    self.network = network
  }

  /// Asks the network for its devices.
  public func load() async {
    state = .loading
    do {
      rows = try await network.devices().map(Self.row)
      state = .loaded
    } catch {
      rows = []
      state = .failed(Self.message(for: error))
    }
  }

  /// Sends a device an on or off command, and shows it on or off once the network acknowledges.
  public func turn(_ row: DeviceRow, on: Bool) async {
    guard row.canSwitch, let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
    notice = nil
    do {
      _ = try await network.execute(ServiceCommand(address: row.id, action: on ? .on : .off))
      rows[index].level = on ? .percent(100) : .off
    } catch {
      notice = Self.message(for: error)
    }
  }

  private static func row(_ device: ServiceDevice) -> DeviceRow {
    let level: DeviceRow.Level =
      switch device.value {
      case nil: .unknown
      case 0?: .off
      case let value?: .percent(Int((Double(value) * 100 / 255).rounded()))
      }
    return DeviceRow(
      id: device.address, title: device.productName ?? "Unidentified device", subtitle: device.address.description,
      canSwitch: device.canTurnOnAndOff, canDim: device.canDim, level: level)
  }

  private static func message(for error: any Error) -> String {
    if let message = InsteonErrorDescription.message(for: error) { return message }
    switch error as? ServiceControlError {
    case .busy?: return "The service is busy with another request. Try again."
    case .modemUnavailable?: return "The service can't reach its modem right now."
    case .notLinked?: return "That device isn't linked to the modem."
    case .notIdentified?: return "That device hasn't said what it is yet."
    case .unsupportedControl?: return "That device has no on and off control."
    case .invalidLevel?, .unknownDevice?: return "The service doesn't know that device."
    case nil: return "The service couldn't be reached."
    }
  }
}
