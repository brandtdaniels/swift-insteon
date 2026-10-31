#if os(macOS) || os(Linux)
import Dispatch
import Testing
import InsteonModem
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Exercises the real POSIX code path against a pseudo-terminal standing in for a modem.
struct SerialPortTests {

  @Test(.timeLimit(.minutes(1)))
  func exchangesBytesWithTheDevice() async throws {

    let (controller, path) = try #require(openPseudoTerminal())
    defer { _ = close(controller) }

    let port = try SerialPort(path: path)
    defer { port.close() }

    // Host to modem.
    try await port.write([0x02, 0x60])

    // A read can return part of what was written, so read until the whole frame arrives.
    var sent: [UInt8] = []

    while sent.count < 2 {

      var buffer = [UInt8](repeating: 0, count: 16)
      let count = read(controller, &buffer, buffer.count)
      try #require(count > 0)
      sent += buffer.prefix(count)

    }

    #expect(sent == [0x02, 0x60])

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

  @Test(.timeLimit(.minutes(1)))
  func closingFinishesTheReceiveStream() async throws {

    let (controller, path) = try #require(openPseudoTerminal())
    defer { _ = close(controller) }

    let port = try SerialPort(path: path)
    let received = port.receive()

    port.close()

    for try await _ in received {}

  }

  @Test(.timeLimit(.minutes(1)))
  func receivingAgainFinishesThePreviousStream() async throws {

    let (controller, path) = try #require(openPseudoTerminal())
    defer { _ = close(controller) }

    let port = try SerialPort(path: path)
    defer { port.close() }

    let first = port.receive()
    _ = port.receive()

    for try await _ in first {}

  }

  @Test(.timeLimit(.minutes(1)))
  func receivingAfterClosingFinishesAtOnce() async throws {

    let (controller, path) = try #require(openPseudoTerminal())
    defer { _ = close(controller) }

    let port = try SerialPort(path: path)
    port.close()

    for try await _ in port.receive() {}

  }

  @Test(.timeLimit(.minutes(1))) func writingAfterClosingThrows() async throws {

    let (controller, path) = try #require(openPseudoTerminal())
    defer { _ = close(controller) }

    let port = try SerialPort(path: path)
    port.close()

    await #expect(throws: SerialPortError.closed) {

      try await port.write([0x02, 0x60])

    }

  }

  // Nothing reads the pseudo-terminal's other end, so the port stops taking bytes and the
  // write waits until it's canceled.
  @Test(.timeLimit(.minutes(1)))
  func cancelingAWriteThePortStoppedTakingEndsIt() async throws {

    let (controller, path) = try #require(openPseudoTerminal())
    defer { _ = close(controller) }

    let port = try SerialPort(path: path)
    defer { port.close() }

    let writing = Task { () async throws -> Void in

      try await port.write([UInt8](repeating: 0x55, count: 1 << 20))

    }

    // A byte arriving means the write has started.
    try #require(await readByte(from: controller) != nil)

    writing.cancel()

    await #expect(throws: CancellationError.self) {

      try await writing.value

    }

  }

  @Test(.timeLimit(.minutes(1)))
  func closingThePortEndsAWriteItStoppedTaking() async throws {

    let (controller, path) = try #require(openPseudoTerminal())
    defer { _ = close(controller) }

    let port = try SerialPort(path: path)
    let writing = Task { () async throws -> Void in

      try await port.write([UInt8](repeating: 0x55, count: 1 << 20))

    }

    try #require(await readByte(from: controller) != nil)

    port.close()

    await #expect(throws: SerialPortError.closed) {

      try await writing.value

    }

  }

  @Test func reportsAMissingDevice() {

    let error: SerialPortError? = #expect(throws: SerialPortError.self) {

      try SerialPort(path: "/dev/insteon-modem-that-does-not-exist")

    }

    guard case let .cannotOpen(path, code)? = error else {

      Issue.record("Expected cannotOpen, got \(String(describing: error)).")

      return

    }

    #expect(path == "/dev/insteon-modem-that-does-not-exist")
    #expect(code == ENOENT)

  }

}

/// Reads one byte on a thread of its own, so the blocking read doesn't hold a thread the tests'
/// tasks run on.
private func readByte(from descriptor: Int32) async -> UInt8? {

  await withCheckedContinuation { (continuation: CheckedContinuation<UInt8?, Never>) in

    DispatchQueue.global().async {

      var byte: UInt8 = 0

      continuation.resume(returning: read(descriptor, &byte, 1) == 1 ? byte : nil)

    }

  }

}

/// Opens a pseudo-terminal, returning its controller descriptor and the path of its peer.
private func openPseudoTerminal() -> (controller: Int32, path: String)? {

  #if os(Linux)
  // Glibc's pseudo-terminal functions aren't imported into Swift, so look them up at run time.
  typealias Function = @convention(c) (Int32) -> Int32
  typealias NameFunction = @convention(c) (Int32) -> UnsafeMutablePointer<CChar>?
  guard
    let grantpt = dlsym(nil, "grantpt").map({ unsafeBitCast($0, to: Function.self) }),
    let unlockpt = dlsym(nil, "unlockpt").map({ unsafeBitCast($0, to: Function.self) }),
    let ptsname = dlsym(nil, "ptsname").map({ unsafeBitCast($0, to: NameFunction.self) })
  else { return nil }
  #endif

  let controller = open("/dev/ptmx", O_RDWR | O_NOCTTY)
  guard controller >= 0 else { return nil }

  guard grantpt(controller) == 0, unlockpt(controller) == 0, let name = ptsname(controller) else {

    _ = close(controller)
    return nil

  }

  return (controller, String(cString: name))

}

#endif
