import Foundation

/// Where files are created, so the choice of where an observation goes can be tested.
public protocol ObservationFiles {

  /// Creates a file with the data, only if no file is at the path.
  ///
  /// - Parameters:
  ///   - data: The file's contents.
  ///   - path: The file's path.
  /// - Returns: `false` if a file is already there, in which case nothing is written.
  /// - Throws: Why the file can't be written.
  func createFile(_ data: Data, at path: String) throws -> Bool

}

/// Where an observation went.
public enum ObservationDelivery: Hashable, Sendable {

  /// Standard output carries the JSON, without its final newline.
  case standardOutput(String)

  /// A file at the path holds the JSON.
  case file(String)

  /// Puts an observation's JSON in the file `--output` names, or on standard output when no
  /// path is given.
  ///
  /// - Parameters:
  ///   - json: The JSON.
  ///   - path: The path given with `--output`, or `nil`.
  ///   - files: Where files are created.
  /// - Returns: Where the JSON went.
  /// - Throws: `CommandFailure` if a file is already at the path, and what `files` throws.
  public static func deliver(_ json: Data, to path: String?, files: some ObservationFiles) throws -> ObservationDelivery {

    guard let path else {

      return .standardOutput(String(decoding: json, as: UTF8.self).trimmingCharacters(in: .newlines))

    }

    guard try files.createFile(json, at: path) else {

      throw CommandFailure(description: "\(path) already exists, so nothing was written. Give --output another path, or remove the file first.")

    }

    return .file(path)

  }

}

/// What `insteon observe` prints beside the file, on standard error.
public enum ObservationText {

  /// The lines that name the device and list the checks, each with its outcome and detail.
  ///
  /// - Parameter observation: The observation.
  /// - Returns: The lines.
  public static func summary(_ observation: Observation) -> [String] {

    let findings: ObservationFindings = observation.findings
    let engine: String = findings.engine ?? "unknown"
    var heading: String

    if let model = findings.model {

      heading = "Observed \(model)"

    } else if let category = findings.category, let subcategory = findings.subcategory {

      heading = "Observed a device of category \(category) and subcategory \(subcategory)"

    } else {

      heading = "Observed a device"

    }

    heading += ", engine \(engine):"

    let checks: [ObservationCheckResult] = findings.checks
    let outcomeWidth: Int = ObservationOutcome.widest
    let nameWidth: Int = checks.map(\.name.count).max() ?? 0
    var lines: [String] = [heading, ""]

    for check in checks {

      let outcome: String = check.outcome.rawValue.padding(toLength: outcomeWidth, withPad: " ", startingAt: 0)
      let name: String = check.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)

      lines.append("\(outcome)  \(name)  \(check.detail)")

    }

    return lines

  }

  /// The lines that tell where the observation went.
  ///
  /// - Parameter delivery: Where it went.
  /// - Returns: The lines, none when it went to standard output.
  public static func closing(_ delivery: ObservationDelivery) -> [String] {

    switch delivery {
    case .standardOutput:
      []
    case let .file(path):
      [
        "Wrote \(path). It holds no address of a device, the modem or a Hub, and no account data; "
          + "look it over, then attach it to an issue or a pull request."
      ]
    }

  }

}

extension ObservationOutcome {

  /// The length of the longest outcome's name.
  static let widest: Int = [ObservationOutcome.answered, .silent, .refused].map(\.rawValue.count).max() ?? 0

}
