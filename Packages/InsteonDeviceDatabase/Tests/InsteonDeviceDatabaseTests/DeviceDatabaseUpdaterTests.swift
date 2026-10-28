import Crypto
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonDeviceDatabase
import InsteonNetworking

/// Answers each request with the response for the file it asks for, and records the files.
actor PublishedFiles: HTTPClient {

  private let responses: [String: HTTPResponse]

  private(set) var urls: [URL] = []

  var requested: [String] {

    urls.map(\.lastPathComponent)

  }

  init(_ responses: [String: HTTPResponse]) {

    self.responses = responses

  }

  func send(_ request: URLRequest) async throws -> HTTPResponse {

    guard let url = request.url else {

      return HTTPResponse(statusCode: 400)

    }

    urls.append(url)

    return responses[url.lastPathComponent] ?? HTTPResponse(statusCode: 404)

  }

}

struct DeviceDatabaseUpdaterTests {

  static let published = DeviceDatabaseTests.json(DeviceDatabaseTests.leakSensor)

  static func sha256(of data: Data) -> String {

    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

  }

  static func manifest(sha256: String, database: String = "database.json", schemaVersion: Int = 1) -> HTTPResponse {

    HTTPResponse(statusCode: 200, body: Data(#"{ "schemaVersion": \#(schemaVersion), "devices": 1, "database": "\#(database)", "sha256": "\#(sha256)" }"#.utf8))

  }

  static func files(manifest: HTTPResponse, database: Data = published) -> PublishedFiles {

    PublishedFiles(["manifest.json": manifest, "database.json": HTTPResponse(statusCode: 200, body: database)])

  }

  @Test func downloadsADifferentDatabase() async throws {

    let files = Self.files(manifest: Self.manifest(sha256: Self.sha256(of: Self.published)))

    let update = try await DeviceDatabaseUpdater(client: files).update(replacing: Data("{}".utf8))
    let expected = try DeviceDatabase(json: Self.published)

    #expect(update == .updated(json: Self.published, database: expected))
    #expect(await files.requested == ["manifest.json", "database.json"])

  }

  @Test func stopsAtTheManifestWhenNothingChanged() async throws {

    let files = Self.files(manifest: Self.manifest(sha256: Self.sha256(of: Self.published)))

    let update = try await DeviceDatabaseUpdater(client: files).update(replacing: Self.published)

    #expect(update == .unchanged)
    #expect(await files.requested == ["manifest.json"])

  }

  @Test func comparesWithTheBundledCopyByDefault() async throws {

    let files = Self.files(manifest: Self.manifest(sha256: Self.sha256(of: try DeviceDatabase.bundledJSON())))

    let update = try await DeviceDatabaseUpdater(client: files).update(replacing: nil)

    #expect(update == .unchanged)
    #expect(await files.requested == ["manifest.json"])

  }

  // A cache can't answer with an older database for a request that names the new one's hash.
  @Test func namesTheExpectedHashInTheDatabaseRequest() async throws {

    let digest = Self.sha256(of: Self.published)
    let files = Self.files(manifest: Self.manifest(sha256: digest))

    _ = try await DeviceDatabaseUpdater(client: files).update(replacing: nil)

    #expect(await files.urls.last?.query == "sha256=\(digest)")

  }

  @Test func refusesADatabaseThatDoesntMatchTheManifest() async {

    let files = Self.files(manifest: Self.manifest(sha256: Self.sha256(of: Data("older".utf8))))

    await #expect(throws: DeviceDatabaseUpdateError.checksumMismatch) {

      try await DeviceDatabaseUpdater(client: files).update(replacing: nil)

    }

  }

  @Test func keepsTheCopyForAnotherFormatVersion() async {

    let files = Self.files(manifest: Self.manifest(sha256: Self.sha256(of: Self.published), schemaVersion: 2))

    await #expect(throws: DeviceDatabaseError.unsupportedSchemaVersion(2)) {

      try await DeviceDatabaseUpdater(client: files).update(replacing: nil)

    }

    #expect(await files.requested == ["manifest.json"])

  }

  @Test(arguments: ["../database.json", "https:", "", ".hidden", "databáse.json"])
  func refusesAManifestNamingAnotherPlace(_ database: String) async {

    let files = Self.files(manifest: Self.manifest(sha256: Self.sha256(of: Self.published), database: database))

    await #expect(throws: DeviceDatabaseUpdateError.malformedManifest) {

      try await DeviceDatabaseUpdater(client: files).update(replacing: nil)

    }

  }

  @Test func refusesADigestThatIsntASCIIHexadecimal() async {

    let files = Self.files(manifest: Self.manifest(sha256: String(repeating: "\u{FF41}", count: 64)))

    await #expect(throws: DeviceDatabaseUpdateError.malformedManifest) {

      try await DeviceDatabaseUpdater(client: files).update(replacing: nil)

    }

    #expect(await files.requested == ["manifest.json"])

  }

  @Test func reportsAFailedRequest() async {

    let files = PublishedFiles(["manifest.json": HTTPResponse(statusCode: 503)])

    await #expect(throws: DeviceDatabaseUpdateError.unexpectedStatus(503)) {

      try await DeviceDatabaseUpdater(client: files).update(replacing: nil)

    }

  }

  @Test func asksForTheFilesInItsLocation() async throws {

    let files = Self.files(manifest: Self.manifest(sha256: Self.sha256(of: Self.published)))
    let location = try #require(URL(string: "https://example.com/mirror/v1/"))

    _ = try await DeviceDatabaseUpdater(client: files, location: location).update(replacing: Self.published)

    #expect(await files.urls.map(\.absoluteString) == ["https://example.com/mirror/v1/manifest.json"])
    #expect(DeviceDatabaseUpdater.defaultLocation.absoluteString == "https://brandtdaniels.github.io/insteon-device-database/v1/")

  }

}
