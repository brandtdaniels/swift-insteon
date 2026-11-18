import Foundation
import RepoCheckSupport

/// Something that runs one check on a tree of files.
public protocol CheckRunning {
  func run(in tree: URL) throws -> CheckOutput
}

/// A failure to start a process.
public struct ProcessLaunchError: Error, CustomStringConvertible {
  public let command: [String]
  public let reason: String

  public var description: String {
    "Can't run \(command.joined(separator: " ")): \(reason)"
  }
}

/// Runs a command with the tree as its working directory and keeps its status and output.
public struct ProcessCheckRunner: CheckRunning {
  private let command: [String]
  private let arguments: (URL) -> [String]

  /// - Parameters:
  ///   - command: The executable's path, then any arguments that come before the rest.
  ///   - arguments: The rest of the arguments, given the tree the check runs on.
  public init(command: [String], arguments: @escaping (URL) -> [String] = { _ in [] }) {
    self.command = command
    self.arguments = arguments
  }

  public func run(in tree: URL) throws -> CheckOutput {
    let scratch = try ScratchDirectory(prefix: "repo-check-run")
    let outputURL = scratch.url(for: "stdout")
    let errorURL = scratch.url(for: "stderr")
    _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    _ = FileManager.default.createFile(atPath: errorURL.path, contents: nil)

    let outputHandle = try FileHandle(forWritingTo: outputURL)
    let errorHandle = try FileHandle(forWritingTo: errorURL)
    defer {
      try? outputHandle.close()
      try? errorHandle.close()
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: command[0])
    process.arguments = Array(command.dropFirst()) + arguments(tree)
    process.currentDirectoryURL = tree
    process.standardOutput = outputHandle
    process.standardError = errorHandle
    process.standardInput = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      throw ProcessLaunchError(command: command, reason: "\(error)")
    }
    process.waitUntilExit()

    return CheckOutput(
      status: process.terminationStatus,
      standardOutput: try Data(contentsOf: outputURL),
      standardError: try Data(contentsOf: errorURL)
    )
  }
}

/// The Python script a check replaces, run as the transitional oracle.
public enum PythonOracle {
  /// A runner of the script in the tree, `Scripts/check-NAME.py`.
  ///
  /// The scripts find the repository from their own location, so each runs from the copy it
  /// checks. `-B` keeps bytecode out of the copy and `-X utf8` fixes the encoding of its output.
  ///
  /// - Parameters:
  ///   - interpreter: The Python command, such as `["/usr/bin/env", "python3"]`.
  ///   - script: The script's path in the tree.
  ///   - arguments: The script's arguments, given the tree.
  public static func runner(
    interpreter: [String],
    script: String,
    arguments: @escaping (URL) -> [String] = { _ in [] }
  ) -> ProcessCheckRunner {
    ProcessCheckRunner(command: interpreter + ["-B", "-X", "utf8"]) { tree in
      [tree.appendingPathComponent(script).path] + arguments(tree)
    }
  }
}
