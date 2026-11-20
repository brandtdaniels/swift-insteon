import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Where a backup is written and read, with the rules that keep it private: readable only by the
/// current user, and never written over a file the person didn't agree to replace.
public enum BackupFile {

  /// The most bytes a file read as a backup may have.
  public static let largestReadableFile: Int = 64 * 1024 * 1024

  /// Refuses a path that holds a file the command isn't allowed to replace, before anything is
  /// read from a modem.
  ///
  /// - Parameters:
  ///   - path: The file the backup goes to.
  ///   - overwrites: Whether `--force` let the command replace a file that's there.
  /// - Throws: ``CommandFailure`` if a file is there and `overwrites` is `false`, or if
  ///   something other than a file is there.
  public static func checkWritable(_ path: String, overwrites: Bool) throws(CommandFailure) {

    var status: stat = stat()

    guard lstat(path, &status) == 0 else {

      return

    }

    guard status.st_mode & 0o170000 == 0o100000 else {

      throw CommandFailure(description: "\(path) exists and isn't a regular file, so nothing was read. Give another path.")

    }

    guard overwrites else {

      throw CommandFailure(description: "\(path) already exists, so nothing was read. Give another path, or add --force to replace it.")

    }

  }

  /// Writes a backup readable only by the current user.
  ///
  /// Without `overwrites`, the file is created only if nothing is there. With it, the contents
  /// are written to a file of their own and moved over the old one, so a failure leaves the old
  /// file as it was.
  ///
  /// - Parameters:
  ///   - data: The backup's bytes.
  ///   - path: The file to write.
  ///   - overwrites: Whether a file that's there may be replaced.
  /// - Throws: ``CommandFailure`` if the file exists and `overwrites` is `false`, or if it can't
  ///   be written.
  public static func write(_ data: Data, to path: String, overwrites: Bool) throws(CommandFailure) {

    if !overwrites {

      try create(path, containing: data)

      return

    }

    let temporary: String = "\(path).\(String(UInt64.random(in: UInt64.min...UInt64.max), radix: 16)).tmp"

    try create(temporary, containing: data)

    guard rename(temporary, path) == 0 else {

      let code: Int32 = errno

      _ = unlink(temporary)

      throw CommandFailure(description: "\(path) couldn't be replaced: \(String(cString: strerror(code))).")

    }

  }

  /// Reads a file to check or plan from.
  ///
  /// - Parameter path: The file.
  /// - Returns: Its contents.
  /// - Throws: ``CommandFailure`` if it can't be read or is too large to be a backup.
  public static func read(_ path: String) throws(CommandFailure) -> Data {

    let descriptor: Int32 = open(path, O_RDONLY | O_NOFOLLOW)

    guard descriptor >= 0 else {

      throw CommandFailure(description: "\(path) couldn't be read: \(String(cString: strerror(errno))).")

    }

    defer { _ = close(descriptor) }

    var status: stat = stat()

    guard fstat(descriptor, &status) == 0, status.st_mode & 0o170000 == 0o100000 else {

      throw CommandFailure(description: "\(path) isn't a regular file.")

    }

    guard status.st_size <= largestReadableFile else {

      throw CommandFailure(description: "\(path) is too large to be a backup.")

    }

    var data: Data = Data()
    var buffer: [UInt8] = [UInt8](repeating: 0, count: 65_536)

    while true {

      let count: Int = buffer.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) -> Int in

        systemRead(descriptor, bytes.baseAddress, bytes.count)

      }

      if count < 0 {

        guard errno == EINTR else {

          throw CommandFailure(description: "\(path) couldn't be read: \(String(cString: strerror(errno))).")

        }

        continue

      }

      if count == 0 {

        return data

      }

      data.append(contentsOf: buffer[0..<count])

    }

  }

  private static func create(_ path: String, containing data: Data) throws(CommandFailure) {

    let descriptor: Int32 = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)

    guard descriptor >= 0 else {

      if errno == EEXIST {

        throw CommandFailure(description: "\(path) already exists, so nothing was written. Give another path, or add --force to replace it.")

      }

      throw CommandFailure(description: "\(path) couldn't be created: \(String(cString: strerror(errno))).")

    }

    // The file's mode is set whatever the process's mask, so it's readable only by its owner.
    _ = fchmod(descriptor, 0o600)

    let written: Bool = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in

      guard let base = buffer.baseAddress else {

        return true

      }

      var offset: Int = 0

      while offset < buffer.count {

        let count: Int = systemWrite(descriptor, base + offset, buffer.count - offset)

        if count < 0 {

          guard errno == EINTR else {

            return false

          }

          continue

        }

        offset += count

      }

      return true

    }

    let writeError: Int32 = errno
    let synced: Bool = written && fsync(descriptor) == 0
    let closed: Bool = close(descriptor) == 0

    guard written, synced, closed else {

      _ = unlink(path)

      throw CommandFailure(description: "\(path) couldn't be written: \(String(cString: strerror(written ? errno : writeError))).")

    }

  }

}

/// The system's `read`, which `BackupFile.read(_:)` hides by name.
private func systemRead(_ descriptor: Int32, _ bytes: UnsafeMutableRawPointer?, _ count: Int) -> Int {

  #if canImport(Darwin)
  return Darwin.read(descriptor, bytes, count)
  #elseif canImport(Glibc)
  return Glibc.read(descriptor, bytes, count)
  #else
  return Musl.read(descriptor, bytes, count)
  #endif

}

/// The system's `write`, which `BackupFile.write(_:to:overwrites:)` hides by name.
private func systemWrite(_ descriptor: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Int {

  #if canImport(Darwin)
  return Darwin.write(descriptor, bytes, count)
  #elseif canImport(Glibc)
  return Glibc.write(descriptor, bytes, count)
  #else
  return Musl.write(descriptor, bytes, count)
  #endif

}
