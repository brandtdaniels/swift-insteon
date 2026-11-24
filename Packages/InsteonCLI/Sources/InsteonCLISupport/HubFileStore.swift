import Foundation

/// Where the `insteon` command reads its environment files from, so the rules for choosing
/// among them can be tested without the real home directory.
///
/// Every path given is absolute. A store never looks in the current directory.
public protocol HubFileStore: Sendable {

  /// Whether a file or directory exists at the path.
  ///
  /// - Parameter path: An absolute path.
  func exists(atPath path: String) -> Bool

  /// The names of the entries in a directory.
  ///
  /// - Parameter path: An absolute path.
  /// - Returns: The names, or `nil` if the directory doesn't exist or can't be listed.
  func fileNames(inDirectory path: String) -> [String]?

  /// Reads an environment file as UTF-8 text, after checking its type, owner and permissions
  /// as ``EnvironmentFile/read(at:warn:)`` does.
  ///
  /// - Parameters:
  ///   - path: An absolute path.
  ///   - warn: Shows a warning, such as that others can read the file.
  /// - Returns: The file's contents.
  /// - Throws: ``EnvironmentFileError`` if the file mustn't or can't be read.
  func read(at path: String, warn: (String) -> Void) throws(EnvironmentFileError) -> String

}

/// The files on disk.
public struct LocalHubFiles: HubFileStore {

  /// Creates a store over the local filesystem.
  public init() {}

  /// Whether a file or directory exists at the path.
  public func exists(atPath path: String) -> Bool {

    FileManager.default.fileExists(atPath: path)

  }

  /// The names of the entries in a directory, sorted, or `nil` if it can't be listed.
  public func fileNames(inDirectory path: String) -> [String]? {

    try? FileManager.default.contentsOfDirectory(atPath: path).sorted()

  }

  /// Reads the file with ``EnvironmentFile/read(at:warn:)``, which checks its type, owner and
  /// permissions on the path and again on the open file.
  public func read(at path: String, warn: (String) -> Void) throws(EnvironmentFileError) -> String {

    try EnvironmentFile.read(at: path, warn: warn)

  }

}
