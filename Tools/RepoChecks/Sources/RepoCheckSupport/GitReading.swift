import Foundation

/// What a check reads from git.
public protocol GitReading {
  /// Whether the path exists at the ref.
  func fileExists(ref: String, path: String) -> Bool

  /// The file's bytes at the ref.
  func show(ref: String, path: String) throws -> [UInt8]

  /// `git diff --no-color --unified=0 REF -- PATH`: the changes from the ref to the working tree.
  func diff(ref: String, path: String) throws -> [UInt8]
}

/// Reads from the git repository in a directory by running `git`.
public struct GitProcess: GitReading {
  private let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  public func fileExists(ref: String, path: String) -> Bool {
    (try? run(["cat-file", "-e", "\(ref):\(path)"])) != nil
  }

  public func show(ref: String, path: String) throws -> [UInt8] {
    try run(["show", "\(ref):\(path)"])
  }

  public func diff(ref: String, path: String) throws -> [UInt8] {
    try run(["diff", "--no-color", "--unified=0", ref, "--", path])
  }

  private func run(_ arguments: [String]) throws -> [UInt8] {
    let scratch = try ScratchDirectory(prefix: "repo-check-git")
    let output = scratch.url(for: "out")
    _ = FileManager.default.createFile(atPath: output.path, contents: nil)
    let handle = try FileHandle(forWritingTo: output)
    defer { try? handle.close() }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = directory
    process.standardOutput = handle
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      throw CheckFailure("git \(arguments.joined(separator: " ")) failed with status \(process.terminationStatus)")
    }
    return Array(try Data(contentsOf: output))
  }
}
