import Foundation

/// What one run of a check produced.
public struct CheckOutput: Equatable, Sendable {
  public var status: Int32
  public var standardOutput: Data
  public var standardError: Data

  public init(status: Int32, standardOutput: Data = Data(), standardError: Data = Data()) {
    self.status = status
    self.standardOutput = standardOutput
    self.standardError = standardError
  }

  /// Standard output as text, for reports.
  public var outputText: String {
    String(decoding: standardOutput, as: UTF8.self)
  }

  /// Standard error as text, for reports.
  public var errorText: String {
    String(decoding: standardError, as: UTF8.self)
  }

  /// Whether Python stopped on an uncaught exception, which it reports as a traceback.
  var isPythonTraceback: Bool {
    errorText.hasPrefix("Traceback (most recent call last):")
  }
}

/// How two runs of the same check on the same tree compare.
public enum Comparison: Equatable, Sendable {
  /// The status, standard output and standard error are the same bytes.
  case identical

  /// Python stopped on an uncaught exception and the Swift check stopped with the same status
  /// and a message on standard error. Their messages can't be the same text.
  case matchingCrash

  /// They differ, in the named streams.
  case differs([String])

  public var isDifference: Bool {
    if case .differs = self {
      return true
    }
    return false
  }

  /// Compares the oracle's run, which is Python's, with the candidate's, which is Swift's.
  public init(oracle: CheckOutput, candidate: CheckOutput) {
    if oracle == candidate {
      self = .identical
    } else if oracle.isPythonTraceback, oracle.status == candidate.status,
      oracle.standardOutput == candidate.standardOutput, !candidate.standardError.isEmpty
    {
      self = .matchingCrash
    } else {
      var streams: [String] = []
      if oracle.status != candidate.status {
        streams.append("status")
      }
      if oracle.standardOutput != candidate.standardOutput {
        streams.append("stdout")
      }
      if oracle.standardError != candidate.standardError {
        streams.append("stderr")
      }
      self = .differs(streams)
    }
  }
}
