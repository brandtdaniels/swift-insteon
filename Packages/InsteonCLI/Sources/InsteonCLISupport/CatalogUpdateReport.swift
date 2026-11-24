import Foundation
import InsteonCore

/// What `insteon catalog update` prints and exits with.
public struct CatalogUpdateReport: Hashable, Sendable {

  /// The lines for standard error, in order: progress, then what the update decided.
  public var notes: [String]

  /// The lines for standard output.
  public var output: [String]

  /// The exit status.
  public var status: Int32

  /// Creates a report.
  ///
  /// - Parameters:
  ///   - notes: The lines for standard error.
  ///   - output: The lines for standard output.
  ///   - status: The exit status.
  public init(notes: [String] = [], output: [String] = [], status: Int32 = ExitStatus.success) {

    self.notes = notes
    self.output = output
    self.status = status

  }

}

extension CatalogUpdateOutcome {

  /// What the command prints and exits with for this outcome, after a saved copy is saved.
  ///
  /// - Parameters:
  ///   - explains: Whether `--explain` was given.
  ///   - printsJSON: Whether `--json` was given, which only changes the `--explain` output.
  /// - Returns: The report, without the progress note the update printed before asking.
  /// - Throws: `EncodingError` if the JSON can't be encoded.
  public func report(explains: Bool, printsJSON: Bool) throws -> CatalogUpdateReport {

    switch self {
    case let .refused(refusal):
      guard explains else {

        return CatalogUpdateReport(notes: CatalogRefusalText.summary(refusal), status: ExitStatus.catalogRefused)

      }

      let output: [String] = printsJSON ? [try CatalogRefusalText.explanationJSON(refusal)] : CatalogRefusalText.explanation(refusal)

      return CatalogUpdateReport(
        notes: CatalogRefusalText.opening(refusal) + CatalogRefusalText.staying(refusal),
        output: output,
        status: ExitStatus.catalogRefused
      )
    case let .save(_, version):
      return try unrefused(CatalogText.updated(to: version), status: "updated", exit: ExitStatus.success, explains: explains, printsJSON: printsJSON)
    case let .keep(line):
      return try unrefused(line, status: "kept", exit: ExitStatus.success, explains: explains, printsJSON: printsJSON)
    case let .current(version):
      return try unrefused(CatalogText.upToDate(version), status: "current", exit: ExitStatus.catalogCurrent, explains: explains, printsJSON: printsJSON)
    }

  }

  private func unrefused(_ line: String, status: String, exit: Int32, explains: Bool, printsJSON: Bool) throws -> CatalogUpdateReport {

    guard explains else {

      return CatalogUpdateReport(output: [line], status: exit)

    }

    if printsJSON {

      return CatalogUpdateReport(output: [try CatalogRefusalText.noDifferencesJSON(status: status)], status: exit)

    }

    return CatalogUpdateReport(output: [line, "No safeguard differences to list."], status: exit)

  }

}

extension CatalogUpdate {

  /// Runs `insteon catalog update` and says what it prints and exits with: checks the published
  /// catalog, saves it when it's used, and reports the outcome. A failure is a report with the
  /// failure status.
  ///
  /// - Parameters:
  ///   - copies: The copies on disk.
  ///   - isReadable: Whether a cached copy's JSON reads as a catalog.
  ///   - location: Where the catalog is published.
  ///   - download: Asks the site, as in ``check(_:isReadable:location:willAsk:download:message:)``.
  ///   - message: Describes an error the download threw.
  ///   - save: Saves a catalog to use, its JSON and version.
  ///   - explains: Whether `--explain` was given.
  ///   - printsJSON: Whether `--json` was given.
  /// - Returns: The report.
  /// - Throws: `CancellationError` if the update was canceled.
  public static func perform(
    _ copies: some CatalogCopies,
    isReadable: (Data) -> Bool,
    location: URL,
    download: (_ current: Data?, _ currentVersion: DeviceCatalogVersion?) async throws -> ProductCatalogUpdate,
    message: (any Error) -> String,
    save: (Data, DeviceCatalogVersion) throws -> Void,
    explains: Bool,
    printsJSON: Bool
  ) async throws -> CatalogUpdateReport {

    var notes: [String] = []

    do {

      let outcome: CatalogUpdateOutcome = try await check(
        copies,
        isReadable: isReadable,
        location: location,
        willAsk: { notes.append($0) },
        download: download,
        message: message
      )

      if case let .save(json, version) = outcome {

        try save(json, version)

      }

      var report: CatalogUpdateReport = try outcome.report(explains: explains, printsJSON: printsJSON)

      report.notes = notes + report.notes

      return report

    } catch let error as CancellationError {

      throw error

    } catch {

      return CatalogUpdateReport(notes: notes + ["insteon: \(Names.message(for: error))"], status: ExitStatus.status(for: error))

    }

  }

}
