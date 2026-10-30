import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Writes files readable only by the current user, replacing a file whole so a reader never
/// sees half of one.
enum PrivateFile {

  /// Writes data to a temporary file of its own, readable only by the current user, then moves it
  /// into place.
  ///
  /// The temporary file has a name no other process can guess, and is created only if nothing, such
  /// as a symbolic link, is already there. The file's directory is created readable only by the
  /// current user, but a directory that's already there is left as it is.
  ///
  /// - Parameters:
  ///   - path: The file's path.
  ///   - data: The file's contents.
  /// - Throws: ``DeviceRegistryStoreError/writeFailed(code:)`` with the system's error code if
  ///   the file couldn't be written, leaving any file already at the path as it was.
  static func replace(_ path: String, with data: Data) throws {

    let suffix: String = String(UInt64.random(in: UInt64.min...UInt64.max), radix: 16)
    let temporary: String = "\(path).\(suffix).tmp"

    try makeDirectory(directory(of: path))
    try createFile(temporary, containing: data)

    guard rename(temporary, path) == 0 else {

      let code: Int32 = errno
      _ = unlink(temporary)

      throw DeviceRegistryStoreError.writeFailed(code: code)

    }

  }

  /// The directory a path is in, such as `/home/example/.cache/insteon` for
  /// `/home/example/.cache/insteon/identities.json`.
  static func directory(of path: String) -> String {

    guard let slash = path.lastIndex(of: "/") else {

      return "."

    }

    return slash == path.startIndex ? "/" : String(path[..<slash])

  }

  /// Makes a directory, readable only by the current user, if it isn't there.
  private static func makeDirectory(_ directory: String) throws {

    let parent: String = self.directory(of: directory)

    if !FileManager.default.fileExists(atPath: parent) {

      do {

        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)

      } catch {

        throw DeviceRegistryStoreError.writeFailed(code: EACCES)

      }

    }

    // A directory that's already there keeps its permissions.
    guard mkdir(directory, 0o700) == 0 || errno == EEXIST else {

      throw DeviceRegistryStoreError.writeFailed(code: errno)

    }

  }

  /// Writes data to a file that doesn't exist yet, readable only by the current user, and
  /// flushes it to storage. A file that can't be written in full is removed.
  private static func createFile(_ path: String, containing data: Data) throws {

    let flags: Int32 = O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW
    let descriptor: Int32 = open(path, flags, 0o600)

    guard descriptor >= 0 else {

      throw DeviceRegistryStoreError.writeFailed(code: errno)

    }

    let written: Bool = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in

      writeAll(buffer, to: descriptor)

    }

    let writeError: Int32 = written ? 0 : errno
    let synced: Bool = written && fsync(descriptor) == 0
    let syncError: Int32 = synced ? 0 : errno
    let closed: Bool = close(descriptor) == 0

    guard synced, closed else {

      let code: Int32 = writeError != 0 ? writeError : (syncError != 0 ? syncError : EIO)
      _ = unlink(path)

      throw DeviceRegistryStoreError.writeFailed(code: code)

    }

  }

  /// Writes every byte of a buffer to a file descriptor, trying again after an interruption.
  private static func writeAll(_ buffer: UnsafeRawBufferPointer, to descriptor: Int32) -> Bool {

    guard let base = buffer.baseAddress else {

      return true

    }

    var offset: Int = 0

    while offset < buffer.count {

      let count: Int = write(descriptor, base + offset, buffer.count - offset)

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

}
