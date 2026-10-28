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

/// Finds Insteon modems on the computer's USB-to-serial adapters.
///
/// Discovery opens each device at 19200 baud and asks it for its modem information with
/// ``Modem/modemInfo()``. A device that answers with a modem's category,
/// `DeviceCategory.networkBridges`, is reported along with what it said about itself. A NAK
/// means a modem that's busy, so it's asked once more. Many modems connect through a common
/// USB-to-serial chip rather than one with Insteon's USB vendor ID, so the answer, rather
/// than the device's vendor, is what identifies a modem.
///
/// ```swift
/// for modem in try await ModemDiscovery().discover() {
///   print(modem.path, modem.info.address)
/// }
/// ```
///
/// Opening a serial device reconfigures it, and some boards, such as Arduino-based ones and 3D
/// printers, restart when they're opened. So discovery lists only the names USB-to-serial
/// adapters take, which PowerLinc Modems use and those boards don't: `/dev/cu.usbserial*`,
/// `/dev/cu.SLAB_USBtoUART*` and `/dev/cu.wchusbserial*` on macOS, and `/dev/ttyUSB*` on Linux.
/// Run it only when the user asks, or give it the paths the user picked with
/// ``ModemDiscovery/init(paths:timeout:)``. A device another program has open may not answer,
/// and a PowerLinc Controller (2414S), which runs IBIOS at 4800 baud, isn't found.
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

  /// Creates a discovery of the computer's USB-to-serial adapters.
  ///
  /// - Parameter timeout: How long each device has to answer. Defaults to
  ///   ``ModemDiscovery/defaultTimeout``.
  public init(timeout: Duration = ModemDiscovery.defaultTimeout) {

    self.init(timeout: timeout, devices: { try ModemDiscovery.usbSerialAdapters() })

  }

  /// Creates a discovery of particular serial devices, such as ones the user picked.
  ///
  /// - Parameters:
  ///   - paths: The serial devices to ask.
  ///   - timeout: How long each device has to answer. Defaults to
  ///     ``ModemDiscovery/defaultTimeout``.
  public init(paths: [String], timeout: Duration = ModemDiscovery.defaultTimeout) {

    self.init(timeout: timeout, devices: { paths })

  }

  private init(timeout: Duration, devices: @escaping @Sendable () throws -> [String]) {

    self.init(
      timeout: timeout,
      devices: devices,
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

  /// Asks each device, all at once, whether it's an Insteon modem.
  ///
  /// - Returns: The modems found, in the order of their paths.
  /// - Throws: The error listing the devices, if they can't be listed, or `CancellationError`
  ///   if the task is canceled.
  public func discover() async throws -> [DiscoveredModem] {

    let paths = try devices()

    let modems = await withTaskGroup(of: DiscoveredModem?.self) { group in

      for path in paths {

        group.addTask {

          await probe(path).map { DiscoveredModem(path: path, info: $0) }

        }

      }

      var modems: [DiscoveredModem] = []

      for await modem in group {

        if let modem {

          modems.append(modem)

        }

      }

      return modems

    }

    try Task.checkCancellation()

    return modems.sorted { $0.path < $1.path }

  }

  /// Asks one device for its modem information, and closes it.
  ///
  /// - Returns: What the device reported, or `nil` if it can't be opened, doesn't answer in
  ///   time, or isn't a modem.
  private func probe(_ path: String) async -> ModemInfo? {

    guard let (connection, close) = try? open(path) else {

      return nil

    }

    defer { close() }

    // A NAK means a busy modem, so it's asked once more.
    let policy = RetryPolicy(attempts: 2, delay: .milliseconds(100), answerTimeout: timeout)

    let info = try? await Modem.withConnection(connection, retryPolicy: policy, clock: clock) { modem in

      try await modem.modemInfo()

    }

    guard let info, info.category == .networkBridges else {

      return nil

    }

    return info

  }

  /// The serial devices USB-to-serial adapters appear as, in path order.
  static func usbSerialAdapters() throws -> [String] {

    #if os(macOS)
    // FTDI and Prolific adapters, Silicon Labs CP210x, and WCH CH340.
    let prefixes = ["cu.usbserial", "cu.SLAB_USBtoUART", "cu.wchusbserial"]
    #else
    // Every USB-to-serial converter driver, but not the CDC-ACM boards on ttyACM.
    let prefixes = ["ttyUSB"]
    #endif

    return try FileManager.default.contentsOfDirectory(atPath: "/dev")
      .filter { name in prefixes.contains { name.hasPrefix($0) } }
      .sorted()
      .map { "/dev/\($0)" }

  }

}
#endif
