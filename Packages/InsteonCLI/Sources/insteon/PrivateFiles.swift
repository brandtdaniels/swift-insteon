import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Reads and writes the command's per-user files in the cache directory, such as the cached
/// Insteon device catalog, readable only by the current user.
enum PrivateFiles {

  /// The contents of a regular file, or `nil` if there's none or it can't be read.
  ///
  /// Only a regular file is read, so a named pipe can't block the command.
  static func read(_ path: String) -> Data? {

    guard
      let type = try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType,
      type == .typeRegular
    else {

      return nil

    }

    return FileManager.default.contents(atPath: path)

  }

  /// Whether there's a file or anything else at a path.
  static func exists(_ path: String) -> Bool {

    FileManager.default.fileExists(atPath: path)

  }

  /// Writes data to a new file of its own, readable only by the current user, then moves it
  /// into place, so a reader never sees half a file.
  ///
  /// The new file has a name no other process can guess, and is created only if nothing,
  /// such as a symbolic link, is already there. The file's directory is created readable only
  /// by the current user, but a directory that's already there is left as it is.
  ///
  /// - Returns: Whether the file was written.
  static func replace(_ path: String, with data: Data) -> Bool {

    let suffix = String(UInt64.random(in: UInt64.min...UInt64.max), radix: 16)
    let temporary = "\(path).\(suffix).tmp"

    guard makeDirectory(Paths.directory(of: path)), createFile(temporary, containing: data) else {

      return false

    }

    guard rename(temporary, path) == 0 else {

      _ = unlink(temporary)

      return false

    }

    return true

  }

  /// Makes a directory, readable only by the current user, if it isn't there.
  ///
  /// - Returns: Whether the directory is there.
  private static func makeDirectory(_ directory: String) -> Bool {

    let parent = Paths.directory(of: directory)

    if !FileManager.default.fileExists(atPath: parent) {

      guard (try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)) != nil else {

        return false

      }

    }

    // A directory that's already there keeps its permissions.
    if mkdir(directory, 0o700) == 0 {

      return true

    }

    return errno == EEXIST

  }

  /// Writes data to a file that doesn't exist yet, readable only by the current user, and
  /// flushes it to storage. A file that can't be written in full is removed.
  ///
  /// - Returns: Whether the file was written.
  private static func createFile(_ path: String, containing data: Data) -> Bool {

    let flags: Int32 = O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW
    let descriptor: Int32 = open(path, flags, 0o600)

    guard descriptor >= 0 else {

      return false

    }

    let written: Bool = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in

      writeAll(buffer, to: descriptor)

    }

    let synced: Bool = written && fsync(descriptor) == 0
    let closed: Bool = close(descriptor) == 0

    guard synced, closed else {

      _ = unlink(path)

      return false

    }

    return true

  }

  /// Writes every byte of a buffer to a file descriptor, trying again after an interruption.
  private static func writeAll(_ buffer: UnsafeRawBufferPointer, to descriptor: Int32) -> Bool {

    guard let base = buffer.baseAddress else {

      return true

    }

    var offset = 0

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

