import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Reads and writes files readable only by the current user, replacing a file whole so a
/// reader never sees half of one.
enum PrivateFile {

  /// The contents of a regular file, or `nil` if there's none, something else is at the path,
  /// such as a directory, a symbolic link or a named pipe, or it can't be read.
  ///
  /// The file is opened without following a symbolic link and without waiting, then checked
  /// to be a regular file through the descriptor it was opened as, so a named pipe can't block
  /// the caller and nothing swapped in between a check and the read is read.
  static func read(_ path: String) -> Data? {

    let descriptor: Int32 = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)

    guard descriptor >= 0 else {

      return nil

    }

    defer { _ = close(descriptor) }

    var status: stat = stat()

    // The file's type, S_IFMT, is a regular file, S_IFREG.
    guard fstat(descriptor, &status) == 0, status.st_mode & 0o170000 == 0o100000 else {

      return nil

    }

    var data: Data = Data()
    var buffer: [UInt8] = [UInt8](repeating: 0, count: 65_536)

    while true {

      let count: Int = buffer.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) -> Int in

        readDescriptor(descriptor, bytes.baseAddress, bytes.count)

      }

      if count < 0 {

        guard errno == EINTR else {

          return nil

        }

        continue

      }

      if count == 0 {

        return data

      }

      data.append(contentsOf: buffer[0..<count])

    }

  }

  /// Whether there's a file, or anything else, at a path.
  static func exists(_ path: String) -> Bool {

    FileManager.default.fileExists(atPath: path)

  }

  /// Writes data to a temporary file of its own, readable only by the current user, then moves it
  /// into place.
  ///
  /// The temporary file has a name no other process can guess, and is created only if nothing, such
  /// as a symbolic link, is already there. The file's own directory is created readable only by
  /// the current user, any directory above it that isn't there is created with the system's
  /// default permissions, and a directory that's already there is left as it is.
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

  /// Makes a directory, readable only by the current user, if it isn't there, after making
  /// any directory above it that isn't there with the system's default permissions.
  private static func makeDirectory(_ directory: String) throws {

    try makeParents(of: directory)

    // A directory that's already there keeps its permissions.
    try makeOne(directory, permissions: 0o700)

  }

  /// Makes the directories above a directory that aren't there, outermost first, with the
  /// system's default permissions, as `mkdir -p` does.
  private static func makeParents(of directory: String) throws {

    let parent: String = self.directory(of: directory)

    guard parent != directory, parent != "/", parent != ".", !FileManager.default.fileExists(atPath: parent) else {

      return

    }

    try makeParents(of: parent)
    try makeOne(parent, permissions: 0o777)

  }

  /// Makes one directory, whose parent is there, unless a directory is already at its path.
  ///
  /// - Throws: ``DeviceRegistryStoreError/writeFailed(code:)`` with the system's error code if
  ///   it couldn't be made, or with `ENOTDIR` if something other than a directory is there.
  private static func makeOne(_ directory: String, permissions: mode_t) throws {

    guard mkdir(directory, permissions) != 0 else {

      return

    }

    let code: Int32 = errno

    guard code == EEXIST else {

      throw DeviceRegistryStoreError.writeFailed(code: code)

    }

    // Something is already there: it must be a directory, or a symbolic link to one, such as
    // a cache directory kept elsewhere, and not a file the write would fail inside.
    var isDirectory: ObjCBool = false

    guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {

      throw DeviceRegistryStoreError.writeFailed(code: ENOTDIR)

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

/// Reads from a file descriptor with the system's `read`, which `PrivateFile.read(_:)` hides by
/// name.
private func readDescriptor(_ descriptor: Int32, _ bytes: UnsafeMutableRawPointer?, _ count: Int) -> Int {

  #if canImport(Darwin)
  return Darwin.read(descriptor, bytes, count)
  #elseif canImport(Glibc)
  return Glibc.read(descriptor, bytes, count)
  #else
  return Musl.read(descriptor, bytes, count)
  #endif

}
