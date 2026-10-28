#if os(macOS) || os(Linux)
import Foundation
import InsteonProtocol

/// A modem that ``ModemDiscovery`` found on a serial port.
public struct DiscoveredModem: Hashable, Sendable {

  /// The serial device the modem is on, such as `/dev/ttyUSB0`.
  public var path: String

  /// What the modem reported about itself: its address, category, subcategory and firmware.
  /// The subcategory names the model; see <doc:SupportedModems>.
  public var info: ModemInfo

  /// Creates a discovered modem.
  ///
  /// - Parameters:
  ///   - path: The serial device the modem is on.
  ///   - info: What the modem reported about itself.
  public init(path: String, info: ModemInfo) {

    self.path = path
    self.info = info

  }

}

/// Finds INSTEON modems on the computer's USB serial ports.
///
/// Discovery lists the serial devices a USB modem appears as, opens each at 19200 baud, and
/// sends Get IM Info (`0x60`). A device that answers with a modem's category, `0x03`, is
/// reported along with what it said about itself. Many modems connect through a common
/// USB-to-serial chip rather than one with SmartLabs' USB vendor ID, so the answer, rather
/// than the device's name, is what identifies a modem.
///
/// ```swift
/// for modem in await ModemDiscovery().discover() {
///   print(modem.path, modem.info.address)
/// }
/// ```
///
/// The devices are asked one at a time, and each that doesn't answer costs
/// ``ModemDiscovery/timeout``. Asking writes two bytes to each listed device, so only the
/// names USB serial adapters take are listed: `/dev/cu.usbserial-*` and `/dev/cu.usbmodem*` on
/// macOS, and `/dev/serial/by-id/*`, or else `/dev/ttyUSB*` and `/dev/ttyACM*`, on Linux. A
/// PowerLinc Controller (2414S) runs IBIOS at 4800 baud rather than the modem commands, so it
/// isn't found. A device another program has open may not answer.
///
/// Available on macOS and Linux.
public struct ModemDiscovery: Sendable {

  /// How long each device has to answer by default: 1 second.
  public static let defaultTimeout: Duration = .seconds(1)

  /// How long each device has to answer.
  public let timeout: Duration

  private let devices: @Sendable () throws -> [String]

  private let open: @Sendable (String) throws -> (connection: any ModemConnection, close: @Sendable () -> Void)

  private let clock: any Clock<Duration>

  /// Creates a discovery of the computer's USB serial ports.
  ///
  /// - Parameter timeout: How long each device has to answer. Defaults to
  ///   ``ModemDiscovery/defaultTimeout``.
  public init(timeout: Duration = ModemDiscovery.defaultTimeout) {

    self.init(
      timeout: timeout,
      devices: { try ModemDiscovery.usbSerialDevices() },
      open: { path in

        let port = try SerialPort(path: path)

        return (port, { port.close() })

      },
      clock: ContinuousClock()
    )

  }

  /// Creates a discovery with its own list of devices, way of opening them and clock, for
  /// tests.
  package init(
    timeout: Duration,
    devices: @escaping @Sendable () throws -> [String],
    open: @escaping @Sendable (String) throws -> (connection: any ModemConnection, close: @Sendable () -> Void),
    clock: any Clock<Duration>
  ) {

    self.timeout = timeout
    self.devices = devices
    self.open = open
    self.clock = clock

  }

  /// Asks each USB serial device whether it's an INSTEON modem.
  ///
  /// - Returns: The modems found, in the order of their paths. Empty if the devices can't be
  ///   listed.
  public func discover() async -> [DiscoveredModem] {

    var modems: [DiscoveredModem] = []

    for path in (try? devices()) ?? [] {

      guard !Task.isCancelled else {

        break

      }

      if let info = await probe(path) {

        modems.append(DiscoveredModem(path: path, info: info))

      }

    }

    return modems

  }

  /// Asks one device for its modem information.
  ///
  /// - Returns: What the device reported, or `nil` if it can't be opened, doesn't answer in
  ///   time, or isn't a modem.
  private func probe(_ path: String) async -> ModemInfo? {

    guard let (connection, close) = try? open(path) else {

      return nil

    }

    defer { close() }

    // One attempt: a device that doesn't answer the first time isn't a modem.
    let policy = RetryPolicy(attempts: 1, answerTimeout: timeout)

    let info = try? await Modem.withConnection(connection, retryPolicy: policy, clock: clock) { modem -> ModemInfo? in

      let replies = await modem.replies()

      try await modem.send(.getModemInfo)

      for await reply in replies {

        if case let .modemInfo(info) = reply {

          return info

        }

      }

      return nil

    }

    // Every INSTEON modem reports category 0x03.
    guard let info, info.category == 0x03 else {

      return nil

    }

    return info

  }

  /// The serial devices USB adapters appear as, in path order.
  static func usbSerialDevices() throws -> [String] {

    let manager = FileManager.default

    #if os(macOS)
    let directory = "/dev"
    let prefixes = ["cu.usbserial", "cu.usbmodem"]
    #else
    // The stable names under by-id point to the same devices as ttyUSB and ttyACM, so they're
    // used instead when there are any.
    let byID = "/dev/serial/by-id"

    if let names = try? manager.contentsOfDirectory(atPath: byID), !names.isEmpty {

      return names.sorted().map { "\(byID)/\($0)" }

    }

    let directory = "/dev"
    let prefixes = ["ttyUSB", "ttyACM"]
    #endif

    return try manager.contentsOfDirectory(atPath: directory)
      .filter { name in prefixes.contains { name.hasPrefix($0) } }
      .sorted()
      .map { "\(directory)/\($0)" }

  }

}
#endif
