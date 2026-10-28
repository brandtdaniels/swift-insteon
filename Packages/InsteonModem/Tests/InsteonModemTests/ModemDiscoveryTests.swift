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

  @Test func findsTheDevicesThatAnswerAsAModem() async {

    let discovery = makeDiscovery([
      "/dev/ttyUSB0": Self.modem(category: 0x03),
      // Something else on a serial port that happens to answer.
      "/dev/ttyUSB1": Self.modem(category: 0x07),
    ])

    let modems = await discovery.discover()

    #expect(modems == [
      DiscoveredModem(
        path: "/dev/ttyUSB0",
        info: ModemInfo(address: InsteonAddress(0x11, 0x22, 0x33), category: 0x03, subcategory: 0x15, firmwareVersion: 0x9E)
      ),
    ])

  }

  @Test func asksForTheModemsInformationAndClosesEachDevice() async {

    let modem = Self.modem(category: 0x03)
    let closed = ClosedDevices()
    let discovery = makeDiscovery(["/dev/ttyUSB0": modem], closed: closed)

    _ = await discovery.discover()

    #expect(modem.written == [[0x02, 0x60]])
    #expect(closed.closed == ["/dev/ttyUSB0"])

  }

  @Test func movesOnFromADeviceThatDoesntAnswer() async {

    let discovery = makeDiscovery([
      "/dev/ttyUSB0": ScriptedConnection { _, _ in [] },
      "/dev/ttyUSB1": Self.modem(category: 0x03),
    ])

    async let modems = discovery.discover()
    await clock.waitForSleeper(until: .seconds(1))
    clock.advance(by: .seconds(1))

    #expect(await modems.map(\.path) == ["/dev/ttyUSB1"])

  }

  @Test func skipsADeviceThatWontOpen() async {

    let listed = ModemDiscovery(
      timeout: .seconds(1),
      devices: { ["/dev/ttyUSB0"] },
      open: { _ in throw SerialPortError.cannotOpen(path: "/dev/ttyUSB0", code: 13) },
      clock: clock
    )

    #expect(await listed.discover().isEmpty)

  }

}
#endif
