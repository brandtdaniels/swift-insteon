import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonDeviceCatalog

@Suite(.timeLimit(.minutes(1)))
struct CatalogUpdateTests {

  // Made-up versions and contents; only their numbers and bytes matter.
  let bundled = DeviceCatalogVersion(major: 0, minor: 6, patch: 20)
  let cachedJSON = Data("cached".utf8)
  let location = URL(string: "https://catalog.example/insteon/")!

  typealias Copies = FakeCatalogCopies

  /// What the download was asked for, and what it answers.
  final class Download {

    var answer: Result<ProductCatalogUpdate, any Error>
    var asked: [(current: Data?, version: DeviceCatalogVersion?)] = []

    init(_ answer: Result<ProductCatalogUpdate, any Error>) {

      self.answer = answer

    }

    func callAsFunction(_ current: Data?, _ version: DeviceCatalogVersion?) throws -> ProductCatalogUpdate {

      asked.append((current, version))

      return try answer.get()

    }

  }

  /// The notes the update printed before asking.
  final class Notes {

    var lines: [String] = []

  }

  private func update(
    _ copies: Copies,
    _ download: Download,
    location: URL? = nil,
    isReadable: (Data) -> Bool = { _ in true },
    notes: Notes = Notes()
  ) async throws -> CatalogUpdateOutcome {

    try await CatalogUpdate.check(
      copies,
      isReadable: isReadable,
      location: location ?? self.location,
      willAsk: { notes.lines.append($0) },
      download: { current, version in try download(current, version) },
      message: { "\($0)" }
    )

  }

  // MARK: - Before asking

  @Test func failsWithoutABundledCopyToUpdateFromAndAsksNothing() async throws {

    let download = Download(.success(.unchanged))
    let notes = Notes()

    await #expect(throws: CommandFailure.self) {

      try await update(Copies(bundled: nil), download, notes: notes)

    }

    #expect(download.asked.isEmpty)

  }

  @Test func failsWithoutACacheDirectoryToKeepTheCopyIn() async throws {

    let download = Download(.success(.unchanged))
    let notes = Notes()

    await #expect(throws: CommandFailure(description: CatalogText.noCacheDirectory)) {

      try await update(Copies(bundled: bundled, catalogPath: nil), download, notes: notes)

    }

    #expect(download.asked.isEmpty)

  }

  @Test func refusesAnAddressThatIsntHTTPSAndAsksNothing() async throws {

    let download = Download(.success(.unchanged))
    let plain = URL(string: "http://catalog.example/insteon/")!
    let notes = Notes()

    await #expect(
      throws: CommandFailure(description: "The Insteon device catalog's address, http://catalog.example/insteon/, isn't HTTPS, so it isn't asked.")
    ) {

      try await update(Copies(bundled: bundled), download, location: plain, notes: notes)

    }

    #expect(download.asked.isEmpty)
    #expect(notes.lines.isEmpty)

  }

  @Test func asksAnHTTPSAddressWhateverTheSchemesCase() async throws {

    let download = Download(.success(.unchanged))
    let upper = URL(string: "HTTPS://catalog.example/insteon/")!

    let outcome = try await update(Copies(bundled: bundled), download, location: upper)

    #expect(download.asked.count == 1)
    #expect(outcome == .keep("The Insteon device catalog is up to date (0.6.20)."))

  }

  // MARK: - Which copy is current

  @Test func comparesTheCachedCopyWhenItsInUse() async throws {

    let cached = DeviceCatalogVersion(major: 0, minor: 6, patch: 21)
    let download = Download(.success(.unchanged))
    let notes = Notes()

    let outcome = try await update(Copies(bundled: bundled, cached: cached, json: cachedJSON), download, notes: notes)

    #expect(download.asked.map(\.current) == [cachedJSON])
    #expect(download.asked.map(\.version) == [cached])
    #expect(outcome == .keep(CatalogText.upToDate(cached)))
    #expect(notes.lines == ["Checking https://catalog.example/insteon/ for a newer Insteon device catalog..."])

  }

  @Test func comparesTheBundledCopyWhenTheCachedOneIsOlder() async throws {

    let older = DeviceCatalogVersion(major: 0, minor: 6, patch: 19)
    let download = Download(.success(.unchanged))
    let notes = Notes()

    let outcome = try await update(Copies(bundled: bundled, cached: older, json: cachedJSON), download, notes: notes)

    #expect(download.asked.count == 1)
    #expect(download.asked.first?.current == nil)
    #expect(download.asked.first?.version == nil)
    #expect(outcome == .keep(CatalogText.upToDate(bundled)))

  }

  @Test func comparesTheBundledCopyWhenTheCachedOneCantBeRead() async throws {

    let cached = DeviceCatalogVersion(major: 0, minor: 6, patch: 21)
    let download = Download(.success(.unchanged))
    let notes = Notes()

    let outcome = try await update(
      Copies(bundled: bundled, cached: cached, json: cachedJSON),
      download,
      isReadable: { _ in false },
      notes: notes
    )

    #expect(download.asked.first?.current == nil)
    #expect(download.asked.first?.version == nil)
    #expect(outcome == .keep(CatalogText.upToDate(bundled)))

  }

  // MARK: - What the site answered

  @Test func savesAPublishedCopyThatDiffers() async throws {

    let published = DeviceCatalogVersion(major: 0, minor: 6, patch: 22)
    let json = Data("published".utf8)
    let notes = Notes()

    let outcome = try await update(Copies(bundled: bundled), Download(.success(.updated(json: json, version: published))), notes: notes)

    #expect(outcome == .save(json: json, version: published))

  }

  @Test func keepsTheCurrentCopyWhenThePublishedOneIsInAnotherFormatOrOlder() async throws {

    let nextMinor = DeviceCatalogVersion(major: 0, minor: 7, patch: 0)
    let older = DeviceCatalogVersion(major: 0, minor: 6, patch: 1)
    let notes = Notes()

    let incompatible = try await update(
      Copies(bundled: bundled),
      Download(.failure(ProductCatalogUpdateError.incompatibleVersion(nextMinor))),
      notes: notes
    )
    let olderOutcome = try await update(Copies(bundled: bundled), Download(.failure(ProductCatalogUpdateError.olderThanCurrent(older))), notes: notes)

    #expect(incompatible == .keep(CatalogText.incompatible(published: nextMinor, bundled: bundled, current: bundled)))
    #expect(olderOutcome == .keep(CatalogText.publishedIsOlder(published: older, current: bundled)))

  }

  @Test func failsWhenThePublishedCopyCantBeUsed() async throws {

    let notes = Notes()

    await #expect(
      throws: CommandFailure(
        description: "The downloaded Insteon device catalog didn't match its manifest's SHA-256, so the current copy, 0.6.20, stays. Try again later."
      )
    ) {

      try await update(Copies(bundled: bundled), Download(.failure(ProductCatalogUpdateError.checksumMismatch)), notes: notes)

    }

    await #expect(
      throws: CommandFailure(description: "The Insteon device catalog's site answered with HTTP status 503, so the current copy, 0.6.20, stays.")
    ) {

      try await update(Copies(bundled: bundled), Download(.failure(ProductCatalogUpdateError.unexpectedStatus(503))), notes: notes)

    }

  }

  @Test func failsOnOneLineWhenTheSiteCantBeReached() async throws {

    struct Unreachable: Error, CustomStringConvertible {

      var description: String { "The site\ncouldn't be reached." }

    }

    let notes = Notes()

    await #expect(
      throws: CommandFailure(
        description: "The Insteon device catalog couldn't be downloaded from https://catalog.example/insteon/: The site couldn't be reached."
      )
    ) {

      try await update(Copies(bundled: bundled), Download(.failure(Unreachable())), notes: notes)

    }

  }

  @Test func passesCancellationOn() async throws {

    let notes = Notes()

    await #expect(throws: CancellationError.self) {

      try await update(Copies(bundled: bundled), Download(.failure(CancellationError())), notes: notes)

    }

  }

}
