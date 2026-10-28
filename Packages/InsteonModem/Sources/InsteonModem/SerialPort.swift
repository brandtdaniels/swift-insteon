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
/// Available on macOS and Linux.
public final class SerialPort: ModemConnection, @unchecked Sendable {

  private let owner: DescriptorOwner

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

    // Writes block until the bytes are accepted; reads are driven by a dispatch source.
    guard
      tcsetattr(descriptor, TCSANOW, &options) == 0,
      fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) & ~O_NONBLOCK) == 0
    else {

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
  /// - Parameter bytes: The bytes to send.
  /// - Throws: ``SerialPortError/closed`` if the port is closed, or
  ///   ``SerialPortError/writeFailed(code:)`` if the port rejects the write.
  public func write(_ bytes: [UInt8]) async throws {

    // The descriptor stays open until this write finishes, even if the port closes meanwhile.
    guard owner.beginUse() else {

      throw SerialPortError.closed

    }

    defer { owner.endUse() }

    let descriptor = owner.descriptor

    try bytes.withUnsafeBytes { buffer in

      var offset = 0

      while offset < buffer.count {

        let written = writeDescriptor(descriptor, buffer.baseAddress! + offset, buffer.count - offset)

        if written < 0 {

          if errno == EINTR {

            continue

          }

          throw SerialPortError.writeFailed(code: errno)

        }

        offset += written

      }

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

/// Owns a port's descriptor, and closes it only once the port is closed and nothing is
/// reading from or writing to it: a closed descriptor's number can be reused by another file,
/// and dispatch requires a descriptor to stay open until every source on it has stopped.
private final class DescriptorOwner: @unchecked Sendable {

  // `lock` guards everything below it; `descriptor` never changes.
  let descriptor: Int32

  private let lock = NSLock()

  private var isClosed = false

  /// Sources that haven't stopped, and writes in progress.
  private var users = 0

  private var reader: ReadSource?

  init(_ descriptor: Int32) {

    self.descriptor = descriptor

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

    let (source, isUnused): (ReadSource?, Bool) = lock.withLock {

      guard !isClosed else {

        return (nil, false)

      }

      isClosed = true
      defer { reader = nil }

      return (reader, users == 0)

    }

    source?.dispatchSource.cancel()

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
