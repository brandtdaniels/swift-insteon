#if os(macOS) || os(Linux)
import Dispatch
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A ``ModemConnection`` to a modem on a serial port, such as a PowerLinc Modem 2413U or 2412U
/// connected by USB, a PowerLinc Modem 2413S or 2412S connected by serial cable, or a USB
/// Adapter 2448A7. See <doc:SupportedModems> for every model.
///
/// The port is opened in raw mode at 19200 baud, 8 data bits, no parity and one stop bit, the
/// settings Insteon modems use, without hardware flow control. A PowerLinc Controller 2414S
/// uses 4800 baud instead; see ``SerialPort/BaudRate``. Each command is written in a
/// single call, because the modem discards a command if more than 240 ms pass between its
/// bytes. On macOS, USB modems appear as `/dev/cu.usbserial-*`; on
/// Linux, as `/dev/ttyUSB*`.
///
/// Writing never blocks a thread: while the port can't take more bytes, such as when an
/// adapter has stopped sending, a write waits without holding one, and it ends when its task
/// is canceled, when the port closes, or when the port has taken nothing for
/// ``SerialPort/longestWriteStall``.
///
/// Available on macOS and Linux.
public final class SerialPort: ModemConnection, @unchecked Sendable {

  private let owner: DescriptorOwner

  /// How long a write waits for the port to take more bytes before it fails with `ETIMEDOUT`:
  /// 30 seconds, longer than a full output buffer takes to drain at 4800 baud.
  public static let longestWriteStall: Duration = .seconds(30)

  /// The speed of a serial connection.
  public enum BaudRate: Hashable, Sendable {

    /// 4800 baud, which a PowerLinc Controller 2414S uses.
    case baud4800

    /// 19200 baud, which Insteon modems use.
    case baud19200

    var speed: speed_t {

      switch self {
      case .baud4800: speed_t(B4800)
      case .baud19200: speed_t(B19200)
      }

    }

  }

  /// Opens the serial port at a path and configures it for an Insteon modem.
  ///
  /// - Parameters:
  ///   - path: The device path, such as `/dev/ttyUSB0`.
  ///   - baudRate: The port's speed. Defaults to 19200 baud, for Insteon modems.
  /// - Throws: ``SerialPortError`` if the port can't be opened or configured.
  public init(path: String, baudRate: BaudRate = .baud19200) throws(SerialPortError) {

    // Opening without blocking avoids waiting for a carrier-detect signal the modem doesn't send.
    let descriptor = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)

    guard descriptor >= 0 else {

      throw .cannotOpen(path: path, code: errno)

    }

    var options = termios()

    guard tcgetattr(descriptor, &options) == 0 else {

      let code = errno
      closeDescriptor(descriptor)
      throw .cannotConfigure(path: path, code: code)

    }

    cfmakeraw(&options)
    cfsetispeed(&options, baudRate.speed)
    cfsetospeed(&options, baudRate.speed)
    options.c_cflag |= tcflag_t(CLOCAL | CREAD)
    // Raw mode leaves these as the port last had them.
    options.c_cflag &= ~(tcflag_t(CSTOPB) | tcflag_t(CRTSCTS))

    // The descriptor stays nonblocking: reads are driven by a dispatch source, and a write
    // that the port can't take yet waits on one, so a stuck write can be canceled.
    guard tcsetattr(descriptor, TCSANOW, &options) == 0 else {

      let code = errno
      closeDescriptor(descriptor)
      throw .cannotConfigure(path: path, code: code)

    }

    self.owner = DescriptorOwner(descriptor)

  }

  deinit {

    close()

  }

  /// Writes bytes to the modem, returning once they've all been handed to the port.
  ///
  /// While the port can't take more bytes, the write waits without blocking a thread. Some
  /// bytes may have been written when it throws.
  ///
  /// - Parameter bytes: The bytes to send.
  /// - Throws: ``SerialPortError/closed`` if the port is closed, or closes while the write
  ///   waits; ``SerialPortError/writeFailed(code:)`` if the port rejects the write, with
  ///   `ETIMEDOUT` if it takes nothing for ``SerialPort/longestWriteStall``; or
  ///   `CancellationError` if the task is canceled first.
  public func write(_ bytes: [UInt8]) async throws {

    // The descriptor stays open until this write finishes, even if the port closes meanwhile.
    guard owner.beginUse() else {

      throw SerialPortError.closed

    }

    defer { owner.endUse() }

    let descriptor = owner.descriptor
    var offset = 0

    while offset < bytes.count {

      try Task.checkCancellation()

      let (written, code): (Int, Int32) = bytes.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> (Int, Int32) in

        let written = writeDescriptor(descriptor, buffer.baseAddress! + offset, buffer.count - offset)

        return (written, errno)

      }

      if written >= 0 {

        offset += written

        continue

      }

      if code == EINTR {

        continue

      }

      guard code == EAGAIN || code == EWOULDBLOCK else {

        throw SerialPortError.writeFailed(code: code)

      }

      try await owner.waitUntilWritable(within: Self.longestWriteStall)

    }

  }

  /// Returns the bytes received from the modem as they arrive.
  ///
  /// Calling this again replaces the previous stream, which finishes.
  ///
  /// - Returns: A stream of received byte chunks that finishes when the port closes.
  public func receive() -> AsyncThrowingStream<[UInt8], any Error> {

    AsyncThrowingStream { [owner] continuation in

      // The descriptor stays open until this stream's source stops reading, even if the port
      // closes meanwhile.
      guard owner.beginUse() else {

        continuation.finish()

        return

      }

      let descriptor = owner.descriptor
      let source = ReadSource(
        DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: DispatchQueue(label: "InsteonModem.SerialPort"))
      )

      source.dispatchSource.setEventHandler {

        var buffer = [UInt8](repeating: 0, count: 256)
        let count = buffer.withUnsafeMutableBytes { readDescriptor(descriptor, $0.baseAddress!, $0.count) }
        let code = errno

        if count > 0 {

          continuation.yield(Array(buffer.prefix(count)))

        } else if count == 0 {

          continuation.finish()
          source.dispatchSource.cancel()

        } else if code != EAGAIN && code != EINTR {

          continuation.finish(throwing: SerialPortError.readFailed(code: code))
          source.dispatchSource.cancel()

        }

      }

      // Dispatch calls this once the source has stopped reading.
      source.dispatchSource.setCancelHandler {

        continuation.finish()
        owner.endUse()

      }

      continuation.onTermination = { _ in

        source.dispatchSource.cancel()

      }

      // A source that's canceled before it's resumed never reads, and resuming it lets it be
      // released and run its cancel handler.
      owner.makeReader(source).forEach { $0.dispatchSource.cancel() }
      source.dispatchSource.resume()

    }

  }

  /// Closes the port. Any stream from ``SerialPort/receive()`` finishes, and the descriptor
  /// closes once nothing is reading from or writing to it.
  public func close() {

    owner.close()

  }

}

/// Errors opening or using a ``SerialPort``. Each carries the system's `errno` code.
public enum SerialPortError: Error, Hashable, Sendable {

  /// The device at the path couldn't be opened, for example because it doesn't exist or is in use.
  case cannotOpen(path: String, code: Int32)

  /// The device couldn't be configured as a serial port.
  case cannotConfigure(path: String, code: Int32)

  /// Writing to the port failed.
  case writeFailed(code: Int32)

  /// Reading from the port failed.
  case readFailed(code: Int32)

  /// The port is closed.
  case closed

}

/// Lets a dispatch source be captured by the `Sendable` closures that drive it. Dispatch
/// sources are thread-safe.
private final class ReadSource: @unchecked Sendable {

  let dispatchSource: any DispatchSourceRead

  init(_ dispatchSource: any DispatchSourceRead) {

    self.dispatchSource = dispatchSource

  }

}

/// A write's wait for the port to take more bytes, which ends once, whichever comes first: the
/// port can take more, the task is canceled, the port closes or the wait runs too long.
private final class WriteWait: @unchecked Sendable {

  // `lock` guards everything below it.
  private let lock = NSLock()

  private var continuation: CheckedContinuation<Void, any Error>?

  private var source: (any DispatchSourceWrite)?

  /// How the wait ended, once it has.
  private var result: Result<Void, any Error>?

  /// Starts waiting on a source that's already resumed, or ends the wait at once if it already
  /// ended.
  func start(_ continuation: CheckedContinuation<Void, any Error>, source: any DispatchSourceWrite) {

    let ended: Result<Void, any Error>? = lock.withLock {

      if result == nil {

        self.continuation = continuation
        self.source = source

      }

      return result

    }

    if let ended {

      source.cancel()
      continuation.resume(with: ended)

    }

  }

  /// Ends the wait, if it hasn't ended.
  func finish(_ outcome: Result<Void, any Error>) {

    let (continuation, source): (CheckedContinuation<Void, any Error>?, (any DispatchSourceWrite)?) = lock.withLock {

      guard result == nil else {

        return (nil, nil)

      }

      result = outcome
      defer {

        self.continuation = nil
        self.source = nil

      }

      return (self.continuation, self.source)

    }

    source?.cancel()
    continuation?.resume(with: outcome)

  }

}

/// Owns a port's descriptor, and closes it only once the port is closed and nothing is
/// reading from or writing to it: a closed descriptor's number can be reused by another file,
/// and dispatch requires a descriptor to stay open until every source on it has stopped.
private final class DescriptorOwner: @unchecked Sendable {

  // `lock` guards everything below it; `descriptor` never changes.
  let descriptor: Int32

  private let lock = NSLock()

  private var isClosed = false

  /// Sources that haven't stopped, reading or waiting to write, and writes in progress.
  private var users = 0

  private var reader: ReadSource?

  /// Writes waiting for the port to take more bytes, which closing the port ends.
  private var writeWaits: [ObjectIdentifier: WriteWait] = [:]

  /// The queue that write sources and their time limits run on.
  private let writeQueue = DispatchQueue(label: "InsteonModem.SerialPort.write")

  init(_ descriptor: Int32) {

    self.descriptor = descriptor

  }

  /// Waits until the descriptor can take more bytes. The caller is using the descriptor.
  ///
  /// - Parameter limit: How long to wait before failing with `ETIMEDOUT`.
  /// - Throws: ``SerialPortError/closed`` if the port closes first,
  ///   ``SerialPortError/writeFailed(code:)`` once `limit` passes, or `CancellationError` if
  ///   the task is canceled first.
  func waitUntilWritable(within limit: Duration) async throws {

    let wait = WriteWait()
    let key = ObjectIdentifier(wait)

    let isOpen: Bool = lock.withLock {

      guard !isClosed else {

        return false

      }

      writeWaits[key] = wait
      // The wait's source uses the descriptor until dispatch has stopped it.
      users += 1

      return true

    }

    guard isOpen else {

      throw SerialPortError.closed

    }

    defer { lock.withLock { writeWaits[key] = nil } }

    let descriptor = descriptor
    let queue = writeQueue
    let milliseconds = Int(limit.components.seconds) * 1_000 + Int(limit.components.attoseconds / 1_000_000_000_000_000)

    try await withTaskCancellationHandler {

      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in

        let source = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: queue)

        source.setEventHandler {

          wait.finish(.success(()))

        }

        // Dispatch calls this once the source has stopped.
        source.setCancelHandler { [self] in

          endUse()

        }

        // A source is resumed before it's handed over, so it can always be released.
        source.resume()
        wait.start(continuation, source: source)

        queue.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {

          wait.finish(.failure(SerialPortError.writeFailed(code: ETIMEDOUT)))

        }

      }

    } onCancel: {

      wait.finish(.failure(CancellationError()))

    }

  }

  /// Starts using the descriptor.
  ///
  /// - Returns: `false` if the port is closed, in which case the descriptor mustn't be used.
  func beginUse() -> Bool {

    lock.withLock {

      guard !isClosed else {

        return false

      }

      users += 1

      return true

    }

  }

  /// Stops using the descriptor, closing it if the port is closed and nothing else uses it.
  func endUse() {

    let isLastUser = lock.withLock {

      users -= 1

      return isClosed && users == 0

    }

    if isLastUser {

      closeDescriptor(descriptor)

    }

  }

  /// Makes a source the one reading.
  ///
  /// - Returns: The sources to cancel: the one this replaces, or this one if the port has
  ///   closed since it began using the descriptor.
  func makeReader(_ source: ReadSource) -> [ReadSource] {

    lock.withLock {

      guard !isClosed else {

        return [source]

      }

      defer { reader = source }

      return reader.map { [$0] } ?? []

    }

  }

  /// Closes the port: the reading source is canceled, and the descriptor closes once nothing
  /// uses it.
  func close() {

    let (source, waits, isUnused): (ReadSource?, [WriteWait], Bool) = lock.withLock {

      guard !isClosed else {

        return (nil, [], false)

      }

      isClosed = true
      defer {

        reader = nil
        writeWaits = [:]

      }

      return (reader, Array(writeWaits.values), users == 0)

    }

    source?.dispatchSource.cancel()

    for wait in waits {

      wait.finish(.failure(SerialPortError.closed))

    }

    if isUnused {

      closeDescriptor(descriptor)

    }

  }

}

// `SerialPort` has its own `write` and `close`, so call the system functions through these.

private func writeDescriptor(_ descriptor: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Int {

  #if canImport(Darwin)
  return Darwin.write(descriptor, bytes, count)
  #else
  return Glibc.write(descriptor, bytes, count)
  #endif

}

private func readDescriptor(_ descriptor: Int32, _ bytes: UnsafeMutableRawPointer, _ count: Int) -> Int {

  #if canImport(Darwin)
  return Darwin.read(descriptor, bytes, count)
  #else
  return Glibc.read(descriptor, bytes, count)
  #endif

}

private func closeDescriptor(_ descriptor: Int32) {

  #if canImport(Darwin)
  _ = Darwin.close(descriptor)
  #else
  _ = Glibc.close(descriptor)
  #endif

}
#endif
