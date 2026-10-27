#if os(macOS) || os(Linux)
import Testing
import InsteonModem
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Exercises the real POSIX code path against a pseudo-terminal standing in for a modem.
struct SerialPortTests {

  @Test func exchangesBytesWithTheDevice() async throws {

    let controller = posix_openpt(O_RDWR | O_NOCTTY)
    try #require(controller >= 0)
    defer { _ = close(controller) }
    try #require(grantpt(controller) == 0 && unlockpt(controller) == 0)
    let path = try #require(pseudoTerminalPath(controller))

    let port = try SerialPort(path: path)
    defer { port.close() }

    // Host to modem.
    try await port.write([0x02, 0x60])

    var buffer = [UInt8](repeating: 0, count: 16)
    let count = read(controller, &buffer, buffer.count)
    #expect(Array(buffer.prefix(max(count, 0))) == [0x02, 0x60])

    // Modem to host.
    let received = port.receive()
    let reply: [UInt8] = [0x02, 0x60, 0x11, 0x22, 0x33, 0x03, 0x21, 0x93, 0x06]
    _ = reply.withUnsafeBytes { write(controller, $0.baseAddress, $0.count) }

    var collected: [UInt8] = []

    for try await chunk in received {

      collected += chunk

      if collected.count >= reply.count {

        break

      }

    }

    #expect(collected == reply)

  }

  @Test func reportsAMissingDevice() {

    #expect(throws: SerialPortError.self) {

      try SerialPort(path: "/dev/insteon-modem-that-does-not-exist")

    }

  }

}

/// Returns the device path of a pseudo-terminal's peer.
private func pseudoTerminalPath(_ controller: Int32) -> String? {

  #if os(Linux)
  // Glibc's `ptsname` isn't imported into Swift, so look it up at run time.
  typealias PTSName = @convention(c) (Int32) -> UnsafeMutablePointer<CChar>?
  guard let symbol = dlsym(nil, "ptsname") else { return nil }
  let ptsname = unsafeBitCast(symbol, to: PTSName.self)
  #endif

  return ptsname(controller).map { String(cString: $0) }

}

#endif
