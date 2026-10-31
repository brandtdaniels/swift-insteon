import Crypto
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import InsteonDeviceCatalog
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

/// Answers as `PublishedFiles` does, except that a request for one file throws, as a client
/// does when it refuses that file's redirect.
struct RedirectedFile: HTTPClient {

  let files: PublishedFiles

  let name: String

  let error: HTTPClientError

  func send(_ request: URLRequest) async throws -> HTTPResponse {

    if request.url?.lastPathComponent == name {

      throw error

    }

    return try await files.send(request)

  }

}

@Suite(.timeLimit(.minutes(1)))
struct DeviceCatalogUpdaterTests {

  static let published = DeviceCatalogTests.json(DeviceCatalogTests.leakSensor)

  static func sha256(of data: Data) -> String {

    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

  }

  /// A version in the bundled copy's format, with a made-up PATCH.
  static func compatibleVersion() throws -> String {

    let bundled = try DeviceCatalog.bundledVersion()

    return "\(bundled.major).\(bundled.minor).987"

  }

  static func manifest(sha256: String, catalog: String = "catalog.json", version: String) -> HTTPResponse {

    HTTPResponse(statusCode: 200, body: Data(#"{ "built": "2001-02-03T04:05:06Z", "catalog": "\#(catalog)", "devices": 1, "sha256": "\#(sha256)", "version": "\#(version)" }"#.utf8))

  }

  static func manifest(sha256: String, catalog: String = "catalog.json") throws -> HTTPResponse {

    manifest(sha256: sha256, catalog: catalog, version: try compatibleVersion())

  }

  static func files(manifest: HTTPResponse, catalog: Data = published) -> PublishedFiles {

    PublishedFiles(["manifest.json": manifest, "catalog.json": HTTPResponse(statusCode: 200, body: catalog)])

  }

  @Test func downloadsADifferentCatalog() async throws {

    let files = Self.files(manifest: try Self.manifest(sha256: Self.sha256(of: Self.published)))

    let update = try await DeviceCatalogUpdater(client: files).update(replacing: Data("{}".utf8), currentVersion: nil)
    let expected = try DeviceCatalog(json: Self.published)
    let version = try #require(DeviceCatalogVersion(try Self.compatibleVersion()))

    #expect(update == .updated(json: Self.published, catalog: expected, version: version))
    #expect(await files.requested == ["manifest.json", "catalog.json"])

  }

  @Test func stopsAtTheManifestWhenNothingChanged() async throws {

    let files = Self.files(manifest: try Self.manifest(sha256: Self.sha256(of: Self.published)))

    let update = try await DeviceCatalogUpdater(client: files).update(replacing: Self.published, currentVersion: nil)

    #expect(update == .unchanged)
    #expect(await files.requested == ["manifest.json"])

  }

  @Test func comparesWithTheBundledCopyByDefault() async throws {

    let files = Self.files(manifest: try Self.manifest(sha256: Self.sha256(of: try DeviceCatalog.bundledJSON())))

    let update = try await DeviceCatalogUpdater(client: files).update(replacing: nil, currentVersion: nil)

    #expect(update == .unchanged)
    #expect(await files.requested == ["manifest.json"])

  }

  // A cache can't answer with an older catalog for a request that names the new one's hash.
  @Test func namesTheExpectedHashInTheCatalogRequest() async throws {

    let digest = Self.sha256(of: Self.published)
    let files = Self.files(manifest: try Self.manifest(sha256: digest))

    _ = try await DeviceCatalogUpdater(client: files).update(replacing: nil, currentVersion: nil)

    #expect(await files.urls.last?.query == "sha256=\(digest)")

  }

  @Test func refusesACatalogThatDoesntMatchTheManifest() async throws {

    let files = Self.files(manifest: try Self.manifest(sha256: Self.sha256(of: Data("older".utf8))))

    await #expect(throws: DeviceCatalogUpdateError.checksumMismatch) {

      try await DeviceCatalogUpdater(client: files).update(replacing: nil, currentVersion: nil)

    }

  }

  // Below 1.0, any MINOR can change the format, so only the bundled copy's MAJOR.MINOR is read.
  @Test func keepsTheCopyForAnotherFormat() async throws {

    let bundled = try DeviceCatalog.bundledVersion()
    let others = [
      DeviceCatalogVersion(major: bundled.major, minor: bundled.minor + 1, patch: 0),
      DeviceCatalogVersion(major: bundled.major + 1, minor: bundled.minor, patch: bundled.patch),
      DeviceCatalogVersion(major: bundled.major, minor: bundled.minor + 1, patch: bundled.patch),
    ]

    if bundled.minor > 0 {

      #expect(DeviceCatalogVersion(major: bundled.major, minor: bundled.minor - 1, patch: 99).isCompatible(with: bundled) == false)

    }

    for other in others {

      let files = Self.files(manifest: Self.manifest(sha256: Self.sha256(of: Self.published), version: other.description))

      await #expect(throws: DeviceCatalogUpdateError.incompatibleVersion(other)) {

        try await DeviceCatalogUpdater(client: files).update(replacing: nil, currentVersion: nil)

      }

      #expect(await files.requested == ["manifest.json"])

    }

  }

  // Another PATCH of the same MAJOR.MINOR is in the same format.
  @Test func takesAnotherPatch() async throws {

    let bundled = try DeviceCatalog.bundledVersion()
    let version = DeviceCatalogVersion(major: bundled.major, minor: bundled.minor, patch: bundled.patch + 1)
    let files = Self.files(manifest: Self.manifest(sha256: Self.sha256(of: Self.published), version: version.description))

    let update = try await DeviceCatalogUpdater(client: files).update(replacing: nil, currentVersion: nil)
    let expected = try DeviceCatalog(json: Self.published)

    #expect(update == .updated(json: Self.published, catalog: expected, version: version))

  }

  // MARK: Rolling back

  // A stale cache or a rolled-back site can't take back data a newer copy has.
  @Test func refusesAVersionOlderThanTheCurrentCopy() async throws {

    let bundled = try DeviceCatalog.bundledVersion()
    let current = DeviceCatalogVersion(major: bundled.major, minor: bundled.minor, patch: 990)
    let published = try #require(DeviceCatalogVersion(try Self.compatibleVersion()))
    let files = Self.files(manifest: Self.manifest(sha256: Self.sha256(of: Self.published), version: published.description))

    await #expect(throws: DeviceCatalogUpdateError.olderThanCurrent(published)) {

      try await DeviceCatalogUpdater(client: files).update(replacing: Data("{}".utf8), currentVersion: current)

    }

    // The catalog itself is never downloaded.
    #expect(await files.requested == ["manifest.json"])

  }

  @Test func refusesAVersionOlderThanTheBundledCopy() async throws {

    let bundled = try DeviceCatalog.bundledVersion()

    // A bundled PATCH of 0 has nothing older in its format.
    guard bundled.patch > 0 else {

      return

    }

    let older = DeviceCatalogVersion(major: bundled.major, minor: bundled.minor, patch: bundled.patch - 1)
    let files = Self.files(manifest: Self.manifest(sha256: Self.sha256(of: Self.published), version: older.description))

    await #expect(throws: DeviceCatalogUpdateError.olderThanCurrent(older)) {

      try await DeviceCatalogUpdater(client: files).update(replacing: nil, currentVersion: nil)

    }

    // The bundled copy is the floor even when the app's copy says it's older still.
    let oldest = DeviceCatalogVersion(major: bundled.major, minor: bundled.minor, patch: 0)

    await #expect(throws: DeviceCatalogUpdateError.olderThanCurrent(older)) {

      try await DeviceCatalogUpdater(client: files).update(replacing: Data("{}".utf8), currentVersion: oldest)

    }

  }

  // The same version with other bytes is a republished copy, not an older one.
  @Test func takesTheCurrentVersionWithOtherBytes() async throws {

    let published = try #require(DeviceCatalogVersion(try Self.compatibleVersion()))
    let files = Self.files(manifest: Self.manifest(sha256: Self.sha256(of: Self.published), version: published.description))

    let update = try await DeviceCatalogUpdater(client: files).update(replacing: Data("{}".utf8), currentVersion: published)

    #expect(update == .updated(json: Self.published, catalog: try DeviceCatalog(json: Self.published), version: published))

  }

  // A saved copy in another format isn't the package's to compare with.
  @Test func ignoresACurrentVersionInAnotherFormat() async throws {

    let bundled = try DeviceCatalog.bundledVersion()
    let otherFormat = DeviceCatalogVersion(major: bundled.major, minor: bundled.minor + 1, patch: 0)
    let published = try #require(DeviceCatalogVersion(try Self.compatibleVersion()))
    let files = Self.files(manifest: Self.manifest(sha256: Self.sha256(of: Self.published), version: published.description))

    let update = try await DeviceCatalogUpdater(client: files).update(replacing: Data("{}".utf8), currentVersion: otherFormat)

    #expect(update == .updated(json: Self.published, catalog: try DeviceCatalog(json: Self.published), version: published))

  }

  @Test func theSameDigestIsUnchangedWhateverTheVersions() async throws {

    let bundled = try DeviceCatalog.bundledVersion()
    let current = DeviceCatalogVersion(major: bundled.major, minor: bundled.minor, patch: 990)
    let files = Self.files(manifest: try Self.manifest(sha256: Self.sha256(of: Self.published)))

    let update = try await DeviceCatalogUpdater(client: files).update(replacing: Self.published, currentVersion: current)

    #expect(update == .unchanged)

  }

  @Test func versionsCompareByMajorThenMinorThenPatch() {

    let versions: [DeviceCatalogVersion] = [
      DeviceCatalogVersion(major: 0, minor: 6, patch: 9),
      DeviceCatalogVersion(major: 0, minor: 6, patch: 10),
      DeviceCatalogVersion(major: 0, minor: 7, patch: 0),
      DeviceCatalogVersion(major: 1, minor: 0, patch: 0),
    ]

    #expect(versions.sorted(by: >).sorted() == versions)
    #expect(DeviceCatalogVersion(major: 0, minor: 6, patch: 10) > DeviceCatalogVersion(major: 0, minor: 6, patch: 9))

  }

  // MARK: The size of a file

  @Test func refusesAFileLargerThanItReads() async {

    let body = Data(repeating: 0x20, count: DeviceCatalogUpdater.maximumResponseSize + 1)
    let files = PublishedFiles(["manifest.json": HTTPResponse(statusCode: 200, body: body)])

    await #expect(throws: HTTPClientError.responseTooLarge(limit: DeviceCatalogUpdater.maximumResponseSize)) {

      try await DeviceCatalogUpdater(client: files).update(replacing: nil, currentVersion: nil)

    }

  }

  @Test func theDefaultClientReadsALimitedFile() throws {

    let client: URLSessionHTTPClient = try #require(DeviceCatalogUpdater().client as? URLSessionHTTPClient)

    #expect(client.maximumResponseSize == DeviceCatalogUpdater.maximumResponseSize)

  }

  @Test(arguments: ["0.5", "0.5.1.2", "v0.5.1", "0.5.x", "0..1", "0.5.-1", "0.5.\u{0661}", "0.05.1", "", "99999999999999999999.0.0"])
  func refusesAManifestWithAMalformedVersion(_ version: String) async {

    let files = Self.files(manifest: Self.manifest(sha256: Self.sha256(of: Self.published), version: version))

    await #expect(throws: DeviceCatalogUpdateError.malformedManifest) {

      try await DeviceCatalogUpdater(client: files).update(replacing: nil, currentVersion: nil)

    }

    #expect(await files.requested == ["manifest.json"])

  }

  @Test func refusesAManifestWithoutAVersion() async {

    let body = Data(#"{ "catalog": "catalog.json", "sha256": "\#(Self.sha256(of: Self.published))" }"#.utf8)
    let files = Self.files(manifest: HTTPResponse(statusCode: 200, body: body))

    await #expect(throws: DeviceCatalogUpdateError.malformedManifest) {

      try await DeviceCatalogUpdater(client: files).update(replacing: nil, currentVersion: nil)

    }

  }

  @Test func readsAndWritesAVersion() throws {

    let version = try #require(DeviceCatalogVersion("1.12.0"))

    #expect(version == DeviceCatalogVersion(major: 1, minor: 12, patch: 0))
    #expect(version.description == "1.12.0")
    #expect(version.isCompatible(with: DeviceCatalogVersion(major: 1, minor: 12, patch: 7)))
    #expect(!version.isCompatible(with: DeviceCatalogVersion(major: 1, minor: 11, patch: 0)))

    let encoded = try JSONEncoder().encode([version])
    let decoded = try JSONDecoder().decode([DeviceCatalogVersion].self, from: Data(#"["0.5.3"]"#.utf8))

    #expect(String(decoding: encoded, as: UTF8.self) == #"["1.12.0"]"#)
    #expect(decoded == [DeviceCatalogVersion(major: 0, minor: 5, patch: 3)])

  }

  @Test(arguments: ["../catalog.json", "https:", "", ".hidden", "databáse.json"])
  func refusesAManifestNamingAnotherPlace(_ catalog: String) async throws {

    let files = Self.files(manifest: try Self.manifest(sha256: Self.sha256(of: Self.published), catalog: catalog))

    await #expect(throws: DeviceCatalogUpdateError.malformedManifest) {

      try await DeviceCatalogUpdater(client: files).update(replacing: nil, currentVersion: nil)

    }

  }

  @Test func refusesADigestThatIsntASCIIHexadecimal() async throws {

    let files = Self.files(manifest: try Self.manifest(sha256: String(repeating: "\u{FF41}", count: 64)))

    await #expect(throws: DeviceCatalogUpdateError.malformedManifest) {

      try await DeviceCatalogUpdater(client: files).update(replacing: nil, currentVersion: nil)

    }

    #expect(await files.requested == ["manifest.json"])

  }

  @Test func reportsAFailedRequest() async {

    let files = PublishedFiles(["manifest.json": HTTPResponse(statusCode: 503)])

    await #expect(throws: DeviceCatalogUpdateError.unexpectedStatus(503)) {

      try await DeviceCatalogUpdater(client: files).update(replacing: nil, currentVersion: nil)

    }

  }

  @Test func asksForTheFilesInItsLocation() async throws {

    let files = Self.files(manifest: try Self.manifest(sha256: Self.sha256(of: Self.published)))
    let location = try #require(URL(string: "https://example.com/mirror/v0/"))

    _ = try await DeviceCatalogUpdater(client: files, location: location).update(replacing: Self.published, currentVersion: nil)

    #expect(await files.urls.map(\.absoluteString) == ["https://example.com/mirror/v0/manifest.json"])

  }

  // MARK: Redirects

  @Test func followsRedirectsOnlyToHTTPSOnTheSameHostByDefault() throws {

    let client: URLSessionHTTPClient = try #require(DeviceCatalogUpdater().client as? URLSessionHTTPClient)

    #expect(DeviceCatalogUpdater.redirectPolicy == .sameOriginHTTPSOnly)
    #expect(client.redirectPolicy == .sameOriginHTTPSOnly)

  }

  @Test(arguments: [HTTPClientError.redirectRefused, .insecureRedirect])
  func aRefusedRedirectForTheManifestFailsTheUpdate(_ error: HTTPClientError) async throws {

    let files: PublishedFiles = Self.files(manifest: try Self.manifest(sha256: Self.sha256(of: Self.published)))
    let client: RedirectedFile = RedirectedFile(files: files, name: "manifest.json", error: error)

    await #expect(throws: error) {

      try await DeviceCatalogUpdater(client: client).update(replacing: Data("{}".utf8), currentVersion: nil)

    }

    #expect(await files.requested.isEmpty)

  }

  @Test(arguments: [HTTPClientError.redirectRefused, .insecureRedirect])
  func aRefusedRedirectForTheCatalogFailsTheUpdate(_ error: HTTPClientError) async throws {

    let files: PublishedFiles = Self.files(manifest: try Self.manifest(sha256: Self.sha256(of: Self.published)))
    let client: RedirectedFile = RedirectedFile(files: files, name: "catalog.json", error: error)

    await #expect(throws: error) {

      try await DeviceCatalogUpdater(client: client).update(replacing: Data("{}".utf8), currentVersion: nil)

    }

    #expect(await files.requested == ["manifest.json"])

  }

  // The published path names the MAJOR version.
  @Test func defaultsToThePathOfTheBundledMajorVersion() throws {

    let major = try DeviceCatalog.bundledVersion().major

    #expect(DeviceCatalogUpdater.defaultLocation.absoluteString == "https://brandtdaniels.github.io/insteon-device-catalog/v\(major)/")

  }

}
