#if os(macOS) || os(Linux)
import Foundation
import Testing
import InsteonModem
import InsteonProtocol
import InsteonTestSupport

/// Records which devices were closed.
final class ClosedDevices: @unchecked Sendable {

  private let lock = NSLock()

  private var paths: [String] = []

  var closed: [String] {

    lock.withLock { paths }

  }

  func close(_ path: String) {

    lock.withLock { paths.append(path) }

  }

}

struct ModemDiscoveryTests {

  let clock = TestClock()

  /// A device that answers Get IM Info as a modem of `category`.
  static func modem(category: UInt8) -> ScriptedConnection {

    ScriptedConnection { written, _ in written + [0x11, 0x22, 0x33, category, 0x15, 0x9E, 0x06] }

  }

  func makeDiscovery(_ devices: [String: ScriptedConnection], closed: ClosedDevices = ClosedDevices()) -> ModemDiscovery {

    ModemDiscovery(
      timeout: .seconds(1),
      devices: { devices.keys.sorted() },
      open: { path in

        struct Missing: Error {}

        guard let connection = devices[path] else {

          throw Missing()

        }

        return (connection, { closed.close(path) })

      },
      clock: clock
    )

  }

  @Test func findsTheDevicesThatAnswerAsAModem() async throws {

    let closed = ClosedDevices()
    let discovery = makeDiscovery([
      "/dev/ttyUSB0": Self.modem(category: 0x03),
      // Something else on a serial port that happens to answer.
      "/dev/ttyUSB1": Self.modem(category: 0x07),
    ], closed: closed)

    let modems = try await discovery.discover()

    #expect(modems == [
      DiscoveredModem(
        path: "/dev/ttyUSB0",
        info: ModemInfo(address: InsteonAddress(0x11, 0x22, 0x33), category: 0x03, subcategory: 0x15, firmwareVersion: 0x9E)
      ),
    ])
    #expect(closed.closed.sorted() == ["/dev/ttyUSB0", "/dev/ttyUSB1"])

  }

  // A NAK means the modem is busy, which is still a modem.
  @Test func asksABusyModemAgain() async throws {

    let modem = ScriptedConnection { written, index in

      index == 0 ? [0x15] : written + [0x11, 0x22, 0x33, 0x03, 0x15, 0x9E, 0x06]

    }
    let discovery = makeDiscovery(["/dev/ttyUSB0": modem])

    async let modems = discovery.discover()
    await clock.waitForSleeper(until: .milliseconds(100))
    clock.advance(by: .milliseconds(100))

    let found = try await modems

    #expect(found.map(\.path) == ["/dev/ttyUSB0"])
    #expect(modem.written.count == 2)

  }

  @Test func asksForTheModemsInformationAndClosesEachDevice() async throws {

    let modem = Self.modem(category: 0x03)
    let closed = ClosedDevices()
    let discovery = makeDiscovery(["/dev/ttyUSB0": modem], closed: closed)

    _ = try await discovery.discover()

    #expect(modem.written == [[0x02, 0x60]])
    #expect(closed.closed == ["/dev/ttyUSB0"])

  }

  @Test func movesOnFromADeviceThatDoesntAnswer() async throws {

    let closed = ClosedDevices()
    let discovery = makeDiscovery([
      "/dev/ttyUSB0": ScriptedConnection { _, _ in [] },
      "/dev/ttyUSB1": Self.modem(category: 0x03),
    ], closed: closed)

    async let modems = discovery.discover()
    await clock.waitForSleeper(until: .seconds(1))
    clock.advance(by: .seconds(1))

    let found = try await modems

    #expect(found.map(\.path) == ["/dev/ttyUSB1"])
    #expect(closed.closed.sorted() == ["/dev/ttyUSB0", "/dev/ttyUSB1"])

  }

  @Test func skipsADeviceThatWontOpen() async throws {

    let listed = ModemDiscovery(
      timeout: .seconds(1),
      devices: { ["/dev/ttyUSB0"] },
      open: { _ in throw SerialPortError.cannotOpen(path: "/dev/ttyUSB0", code: 13) },
      clock: clock
    )

    #expect(try await listed.discover().isEmpty)

  }

}
#endif
