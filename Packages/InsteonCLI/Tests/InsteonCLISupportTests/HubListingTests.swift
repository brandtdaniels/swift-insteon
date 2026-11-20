import Testing
import InsteonCLISupport

/// What `insteon hubs` lists: the default file and each Hub file, with the address and the
/// reason a file can't be used.
struct HubListingTests {

  static let configuration = HubFilesTests.configuration

  static let hubs = configuration + "/hubs"

  static func files(_ contents: [String: String]) -> FakeHubFiles {

    FakeHubFiles(contents)

  }

  static func listing(_ store: FakeHubFiles, environment: [String: String] = HubFilesTests.home) -> HubListing {

    HubFiles(store: store, environment: environment).listing()

  }

  static let full = [
    configuration + "/env": HubFilesTests.standard,
    hubs + "/basement.env": HubFilesTests.basement,
    hubs + "/garage.env": HubFilesTests.garage
  ]

  // MARK: - What it lists

  @Test func listsTheDefaultFileThenEachNamedFileInOrder() throws {

    let listing = Self.listing(Self.files(Self.full))

    #expect(listing.entries.map(\.name) == [nil, "basement", "garage"])
    #expect(listing.entries.map(\.path) == [Self.configuration + "/env", Self.hubs + "/basement.env", Self.hubs + "/garage.env"])
    #expect(listing.directory == Self.hubs)

  }

  @Test func showsAnAddressAndPortFromTheFile() {

    let listing = Self.listing(Self.files(Self.full))

    #expect(listing.entries.map(\.address) == ["192.168.1.20", "192.168.1.30:8080", nil])

  }

  @Test func keepsAPortThatTheHostAlreadyHas() {

    let listing = Self.listing(Self.files([Self.hubs + "/a.env": "INSTEON_HUB_HOST=192.168.1.30:9000\nINSTEON_HUB_PORT=8080\n"]))

    #expect(listing.entries.map(\.address) == ["192.168.1.30:9000"])

  }

  @Test func marksTheDefaultFileAsTheDefaultWhenNoVariableNamesAHub() {

    let listing = Self.listing(Self.files(Self.full))

    #expect(listing.entries.map(\.isDefault) == [true, false, false])

  }

  @Test func marksTheHubTheVariableNamesAsTheDefaultInstead() {

    let listing = Self.listing(Self.files(Self.full), environment: HubFilesTests.home.merging(["INSTEON_HUB": "garage"]) { $1 })

    #expect(listing.entries.map(\.isDefault) == [false, false, true])

  }

  @Test func omitsADefaultFileThatDoesNotExist() {

    var contents = Self.full
    contents[Self.configuration + "/env"] = nil

    let listing = Self.listing(Self.files(contents))

    #expect(listing.entries.map(\.name) == ["basement", "garage"])
    #expect(listing.entries.map(\.isDefault) == [false, false])

  }

  @Test func ignoresFilesThatAreNotHubFiles() {

    let listing = Self.listing(Self.files([Self.hubs + "/notes.txt": "x", Self.hubs + "/basement.env": HubFilesTests.basement]))

    #expect(listing.entries.map(\.name) == ["basement"])

  }

  @Test func recordsAVariableHubWithoutAFile() {

    let listing = Self.listing(Self.files(Self.full), environment: HubFilesTests.home.merging(["INSTEON_HUB": "attic"]) { $1 })

    #expect(listing.missingVariableHub == "attic")
    #expect(listing.entries.map(\.isDefault) == [false, false, false])

  }

  // MARK: - What's wrong with a file

  @Test func flagsAFileOthersCanWrite() {

    var store = Self.files(Self.full)
    store.files[Self.hubs + "/basement.env"]?.mode = 0o100_666

    let entry = Self.listing(store).entries[1]

    #expect(entry.problem == .refused(.writableByOthers))
    #expect(entry.address == nil)

  }

  @Test func flagsAFileAnotherUserOwns() {

    var store = Self.files(Self.full)
    store.files[Self.hubs + "/basement.env"]?.ownerID = 0

    #expect(Self.listing(store).entries[1].problem == .refused(.ownedByAnotherUser))

  }

  @Test func flagsAFileThatIsNotARegularFile() {

    var store = Self.files(Self.full)
    store.files[Self.hubs + "/basement.env"]?.mode = 0o040_755

    #expect(Self.listing(store).entries[1].problem == .refused(.notRegularFile))

  }

  @Test func flagsAFileThatCantBeRead() {

    var store = Self.files(Self.full)
    store.unopenable = [Self.hubs + "/basement.env"]

    #expect(Self.listing(store).entries[1].problem == .unreadable)

  }

  @Test func flagsAMalformedFileWithItsLine() {

    let listing = Self.listing(Self.files([Self.hubs + "/basement.env": "INSTEON_HUB_HOST=192.168.1.30\nnot a variable\n"]))

    #expect(listing.entries[0].problem == .malformed(line: 2))

  }

  @Test func showsAFileOthersCanReadButSaysSo() {

    var store = Self.files(Self.full)
    store.files[Self.hubs + "/basement.env"]?.mode = 0o100_644

    let entry = Self.listing(store).entries[1]

    #expect(entry.problem == nil)
    #expect(entry.isReadableByOthers)
    #expect(entry.address == "192.168.1.30:8080")

  }

  @Test func flagsAFileWhoseNameCantBeUsed() {

    let listing = Self.listing(Self.files([Self.hubs + "/Basement.env": HubFilesTests.basement, Self.hubs + "/a.b.env": HubFilesTests.basement]))

    #expect(listing.entries.map(\.problem) == [.unusableName, .unusableName])

  }

  // MARK: - The text

  @Test func showsATableWithTheDefaultMarked() {

    let rows = HubListText.rows(for: Self.listing(Self.files(Self.full)))

    #expect(rows == [
      ["NAME", "ADDRESS", "NOTE"],
      ["(default file)", "192.168.1.20", "default"],
      ["basement", "192.168.1.30:8080"],
      ["garage", "-", "no INSTEON_HUB_HOST; give --hub ADDRESS"]
    ])

  }

  @Test func neverShowsAUserNameOrAPassword() {

    let text = HubListText.rows(for: Self.listing(Self.files(Self.full))).flatMap { $0 }.joined(separator: "\n")

    for secret in ["basement-user", "basement-secret", "garage-user", "garage-secret", "standard-user", "standard-secret"] {

      #expect(!text.contains(secret))

    }

  }

  @Test func givesTheReasonAndTheFixForEachProblem() {

    var store = Self.files(Self.full)
    store.files[Self.hubs + "/basement.env"]?.mode = 0o100_666
    store.files[Self.hubs + "/garage.env"]?.contents = "oops\n"

    let rows = HubListText.rows(for: Self.listing(store))

    #expect(rows[2][2] == "not read: others can write to it; chmod 600 \(Self.hubs)/basement.env")
    #expect(rows[3][2] == "not read: line 1 isn't NAME=VALUE")

  }

  @Test func saysWhenOthersCanReadAFile() {

    var store = Self.files(Self.full)
    store.files[Self.hubs + "/basement.env"]?.mode = 0o100_644

    let rows = HubListText.rows(for: Self.listing(store))

    #expect(rows[2][1] == "192.168.1.30:8080")
    #expect(rows[2][2] == "others can read it; chmod 600 \(Self.hubs)/basement.env")

  }

  @Test func explainsAnotherUsersFileAndAFileThatIsNotRegular() {

    var store = Self.files(Self.full)
    store.files[Self.hubs + "/basement.env"]?.ownerID = 0
    store.files[Self.hubs + "/garage.env"]?.mode = 0o040_700

    let rows = HubListText.rows(for: Self.listing(store))

    #expect(rows[2][2] == "not read: another user owns it")
    #expect(rows[3][2] == "not read: it isn't a regular file")

  }

  @Test func explainsAnUnreadableFileAndAnUnusableName() {

    var store = Self.files([Self.hubs + "/basement.env": HubFilesTests.basement, Self.hubs + "/Garage.env": HubFilesTests.garage])
    store.unopenable = [Self.hubs + "/basement.env"]

    let rows = HubListText.rows(for: Self.listing(store))

    #expect(rows[1][0] == "Garage")
    #expect(rows[1][2] == "unusable name: use a-z, 0-9, hyphen and underscore, 1 to 32 characters")
    #expect(rows[2][0] == "basement")
    #expect(rows[2][2] == "not read: it can't be opened or isn't UTF-8 text")

  }

  @Test func saysWhereItLookedAndHowToCreateAFileWhenThereAreNone() {

    let listing = Self.listing(FakeHubFiles())
    let message = HubListText.emptyMessage(for: listing)

    #expect(HubListText.rows(for: listing).isEmpty)
    #expect(message.hasPrefix("No Hub files"))
    #expect(message.contains(Self.hubs))
    #expect(message.contains("NAME.env"))
    #expect(message.contains("chmod 600"))
    #expect(message.contains("insteon --hub NAME"))

  }

  @Test func saysWhenTheVariableNamesAHubWithoutAFile() {

    let listing = Self.listing(Self.files(Self.full), environment: HubFilesTests.home.merging(["INSTEON_HUB": "attic"]) { $1 })

    #expect(HubListText.notes(for: listing) == ["INSTEON_HUB names 'attic', but \(Self.hubs)/attic.env doesn't exist."])
    #expect(HubListText.notes(for: Self.listing(Self.files(Self.full))).isEmpty)

  }

}
