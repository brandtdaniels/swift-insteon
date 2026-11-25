import Foundation

/// What a check reads from git.
public protocol GitReading {
  /// Whether the path exists at the ref. Throws when the ref itself can't be resolved.
  func fileExists(ref: String, path: String) throws -> Bool

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

  public func fileExists(ref: String, path: String) throws -> Bool {
    // A ref that doesn't resolve is an error, not an absent file.
    _ = try run(["rev-parse", "--verify", "--quiet", "\(ref)^{commit}"])
    return (try? run(["cat-file", "-e", "\(ref):\(path)"])) != nil
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
    let errors = scratch.url(for: "err")
    _ = FileManager.default.createFile(atPath: errors.path, contents: nil)
    let handle = try FileHandle(forWritingTo: output)
    let errorHandle = try FileHandle(forWritingTo: errors)
    defer {
      try? handle.close()
      try? errorHandle.close()
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = directory
    process.standardOutput = handle
    process.standardError = errorHandle
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let reason = (try? String(contentsOf: errors, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let detail = reason.isEmpty ? "" : ": \(reason)"
      throw CheckFailure("git \(arguments.joined(separator: " ")) failed with status \(process.terminationStatus)\(detail)")
    }
    return Array(try Data(contentsOf: output))
  }
}
