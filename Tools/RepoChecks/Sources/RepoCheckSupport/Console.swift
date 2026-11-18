import Foundation

/// Where a check writes its report.
///
/// A line is written with its terminating newline, as Python's `print` writes it.
public protocol Console {
  /// Writes a line to standard output.
  func write(_ line: String)

  /// Writes a line to standard error.
  func writeError(_ line: String)
}

/// A console on the process's standard output and standard error.
public struct StandardConsole: Console {
  public init() {}

  public func write(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
  }

  public func writeError(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
  }
}

/// A console that keeps what it is given, for tests.
public final class RecordingConsole: Console {
  /// Each line written to standard output.
  public private(set) var lines: [String] = []

  /// Each line written to standard error.
  public private(set) var errorLines: [String] = []

  public init() {}

  public func write(_ line: String) {
    lines.append(line)
  }

  public func writeError(_ line: String) {
    errorLines.append(line)
  }

  /// Standard output as it would appear, each line ended by a newline.
  public var output: String {
    lines.map { $0 + "\n" }.joined()
  }
}
