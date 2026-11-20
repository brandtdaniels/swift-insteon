import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

/// What `insteon catalog update` prints and exits with, as the command runs it.
@Suite(.timeLimit(.minutes(1)))
struct CatalogUpdateReportTests {

  let bundled = DeviceCatalogVersion(major: 0, minor: 10, patch: 1)
  let published = DeviceCatalogVersion(major: 0, minor: 10, patch: 39)
  let location = URL(string: "https://catalog.example/insteon/")!
  let checking = "Checking https://catalog.example/insteon/ for a newer Insteon device catalog..."

  final class Saved {

    var versions: [DeviceCatalogVersion] = []

  }

  private func run(
    _ answer: Result<ProductCatalogUpdate, any Error>,
    explains: Bool = false,
    printsJSON: Bool = false,
    saved: Saved = Saved()
  ) async throws -> CatalogUpdateReport {

    try await CatalogUpdate.perform(
      FakeCatalogCopies(bundled: bundled),
      isReadable: { _ in true },
      location: location,
      download: { _, _ in try answer.get() },
      message: { "\($0)" },
      save: { _, version in saved.versions.append(version) },
      explains: explains,
      printsJSON: printsJSON
    )

  }

  var weakenings: [GuardWeakening] {

    [
      CatalogRefusalTextTests.weakening(0x01, 0x21, .effect, "extended cmd1 0x25 actuation to configuration"),
      CatalogRefusalTextTests.weakening(0x03, 0x1F, .effect, "serial 0x64 payload 1 0x00 undescribed to link"),
    ]

  }

  // MARK: - Refused

  @Test func printsTheGroupedSummaryOnStandardErrorAndExitsWithTheRefusedStatus() async throws {

    let report = try await run(.failure(ProductCatalogUpdateError.weakensGuards(weakenings, published: published)))

    #expect(
      report.notes == [
        checking,
        "The published Insteon device catalog, 0.10.39, relaxes safeguards that the bundled copy, 0.10.1,",
        "keeps, so it isn't used.",
        "",
        "2 differences in 2 kinds, across 2 products:",
        "",
        "Effect changes: 1 difference across 1 product",
        "    0x01/0x21  extended cmd1 0x25 actuation to configuration",
        "Undescribed serial commands now described: 1 difference across 1 product",
        "    0x03/0x1F  serial 0x64 payload 1 0x00 undescribed to link",
        "",
        "The bundled copy, 0.10.1, stays until a new version of this tool ships a refreshed bundle.",
        "Run 'insteon catalog update --explain' to see every difference, one per line.",
      ]
    )
    #expect(report.output.isEmpty)
    #expect(report.status == ExitStatus.catalogRefused)
    #expect(report.notes.allSatisfy { $0.count <= 100 })

  }

  @Test func refusesTheSameInputsAsBefore() async throws {

    let saved = Saved()
    let outcome = try await CatalogUpdate.check(
      FakeCatalogCopies(bundled: bundled),
      isReadable: { _ in true },
      location: location,
      willAsk: { _ in },
      download: { _, _ in throw ProductCatalogUpdateError.weakensGuards(weakenings, published: published) },
      message: { "\($0)" }
    )

    #expect(outcome == .refused(CatalogRefusal(published: published, bundled: bundled, current: bundled, weakenings: weakenings)))
    #expect(saved.versions.isEmpty)

  }

  @Test func neverSavesARefusedCatalog() async throws {

    let saved = Saved()

    _ = try await run(.failure(ProductCatalogUpdateError.weakensGuards(weakenings, published: published)), saved: saved)

    #expect(saved.versions.isEmpty)

  }

  @Test func explainsOnStandardOutputWhenRefused() async throws {

    let report = try await run(.failure(ProductCatalogUpdateError.weakensGuards(weakenings, published: published)), explains: true)

    #expect(
      report.output == [
        "Effect changes: 1 difference across 1 product",
        "0x01/0x21 extended cmd1 0x25 actuation to configuration",
        "",
        "Undescribed serial commands now described: 1 difference across 1 product",
        "0x03/0x1F serial 0x64 payload 1 0x00 undescribed to link",
      ]
    )
    #expect(
      report.notes == [
        checking,
        "The published Insteon device catalog, 0.10.39, relaxes safeguards that the bundled copy, 0.10.1,",
        "keeps, so it isn't used.",
        "The bundled copy, 0.10.1, stays until a new version of this tool ships a refreshed bundle.",
      ]
    )
    #expect(report.status == ExitStatus.catalogRefused)

  }

  @Test func explainsAsJSONWhenRefused() async throws {

    let report = try await run(.failure(ProductCatalogUpdateError.weakensGuards(weakenings, published: published)), explains: true, printsJSON: true)

    #expect(report.output.count == 1)
    #expect(report.output[0].contains("\"status\" : \"refused\""))
    #expect(report.status == ExitStatus.catalogRefused)

  }

  // MARK: - Current

  @Test func saysTheCatalogIsCurrentWithItsOwnStatus() async throws {

    let report = try await run(.success(.unchanged))

    #expect(report.notes == [checking])
    #expect(report.output == ["The Insteon device catalog is up to date (0.10.1)."])
    #expect(report.status == ExitStatus.catalogCurrent)

  }

  @Test func explainsThereIsNothingToListWhenCurrent() async throws {

    let report = try await run(.success(.unchanged), explains: true)

    #expect(report.output == ["The Insteon device catalog is up to date (0.10.1).", "No safeguard differences to list."])
    #expect(report.status == ExitStatus.catalogCurrent)

  }

  @Test func explainsCurrentAsJSON() async throws {

    let report = try await run(.success(.unchanged), explains: true, printsJSON: true)

    #expect(report.output.count == 1)
    #expect(report.output[0].contains("\"status\" : \"current\""))
    #expect(report.output[0].contains("\"groups\" : ["))

  }

  // MARK: - Updated

  @Test func savesAndSucceedsWhenTheCatalogIsNewer() async throws {

    let saved = Saved()
    let report = try await run(.success(.updated(json: Data("{}".utf8), version: published)), saved: saved)

    #expect(saved.versions == [published])
    #expect(report.output == ["Updated the Insteon device catalog to 0.10.39."])
    #expect(report.status == ExitStatus.success)

  }

  // MARK: - Unreachable

  @Test func failsWithTheFailureStatusWhenTheSiteCantBeReached() async throws {

    let report = try await run(.failure(URLError(.notConnectedToInternet)))

    #expect(report.notes.first == checking)
    #expect(report.notes.count == 2)
    #expect(report.notes[1].hasPrefix("insteon: The Insteon device catalog couldn't be downloaded from https://catalog.example/insteon/: "))
    #expect(report.output.isEmpty)
    #expect(report.status == ExitStatus.failure)

  }

  @Test func failsWithTheFailureStatusWhenTheSiteAnswersWithAnError() async throws {

    let report = try await run(.failure(ProductCatalogUpdateError.unexpectedStatus(503)))

    #expect(report.notes == [checking, "insteon: The Insteon device catalog's site answered with HTTP status 503, so the current copy, 0.10.1, stays."])
    #expect(report.status == ExitStatus.failure)

  }

  // MARK: - Statuses

  @Test func givesRefusedCurrentAndFailureDistinctStatuses() {

    let statuses: [Int32] = [ExitStatus.success, ExitStatus.failure, ExitStatus.usage, ExitStatus.interrupted, ExitStatus.catalogRefused, ExitStatus.catalogCurrent]

    #expect(Set(statuses).count == statuses.count)
    #expect(ExitStatus.catalogRefused == 3)
    #expect(ExitStatus.catalogCurrent == 4)

  }

  // MARK: - Arguments

  @Test func readsExplainOnTheCatalogUpdateCommandLine() throws {

    #expect(try Invocation.parse(["catalog", "update", "--explain"]).subcommand == .catalogUpdate(explains: true))
    #expect(try Invocation.parse(["catalog", "update"]).subcommand == .catalogUpdate(explains: false))
    #expect(try Invocation.parse(["--json", "catalog", "update", "--explain"]) == Invocation(printsJSON: true, subcommand: .catalogUpdate(explains: true)))
    #expect(throws: ArgumentError.self) { try Invocation.parse(["catalog", "--explain"]) }

  }

}
