import Testing
import InsteonCLISupport

/// Which environment file a command reads, and what it makes of the Hub files in the per-user
/// directory, with the filesystem faked.
struct HubFilesTests {

  static let home = ["HOME": "/home/example"]

  static let configuration = "/home/example/.config/insteon"

  static let basement = "INSTEON_HUB_USERNAME=basement-user\nINSTEON_HUB_PASSWORD=basement-secret\nINSTEON_HUB_HOST=192.168.1.30\nINSTEON_HUB_PORT=8080\n"

  static let garage = "INSTEON_HUB_USERNAME=garage-user\nINSTEON_HUB_PASSWORD=garage-secret\n"

  static let standard = "INSTEON_HUB_USERNAME=standard-user\nINSTEON_HUB_PASSWORD=standard-secret\nINSTEON_HUB_HOST=192.168.1.20\n"

  static func store(_ contents: [String: String] = [:]) -> FakeHubFiles {

    var files: [String: String] = [
      configuration + "/env": standard,
      configuration + "/hubs/basement.env": basement,
      configuration + "/hubs/garage.env": garage
    ]

    for (path, text) in contents {

      files[path] = text

    }

    return FakeHubFiles(files)

  }

  static func load(
    explicitPath: String? = nil,
    hubName: String? = nil,
    environment: [String: String] = home,
    store: FakeHubFiles = store(),
    warnings: inout [String]
  ) throws -> [String: String] {

    var collected: [String] = []
    defer { warnings.append(contentsOf: collected) }

    return try HubFiles(store: store, environment: environment).load(explicitPath: explicitPath, hubName: hubName, warn: { (text: String) -> Void in collected.append(text) })

  }

  static func load(explicitPath: String? = nil, hubName: String? = nil, environment: [String: String] = home, store: FakeHubFiles = store()) throws -> [String: String] {

    var ignored: [String] = []

    return try load(explicitPath: explicitPath, hubName: hubName, environment: environment, store: store, warnings: &ignored)

  }

  // MARK: - Where the files are

  @Test func keepsHubFilesInAHubsDirectoryNextToTheEnvironmentFile() {

    let files = HubFiles(store: Self.store(), environment: Self.home)

    #expect(files.hubsDirectory == "/home/example/.config/insteon/hubs")
    #expect(files.path(forName: "basement") == "/home/example/.config/insteon/hubs/basement.env")

  }

  @Test func followsXDGConfigHome() {

    let files = HubFiles(store: Self.store(), environment: ["XDG_CONFIG_HOME": "/xdg/config", "HOME": "/home/example"])

    #expect(files.hubsDirectory == "/xdg/config/insteon/hubs")

  }

  @Test func ignoresARelativeXDGConfigHome() {

    let files = HubFiles(store: Self.store(), environment: ["XDG_CONFIG_HOME": "config", "HOME": "/home/example"])

    #expect(files.hubsDirectory == "/home/example/.config/insteon/hubs")

  }

  @Test func hasNoDirectoryWithoutAHome() {

    let files = HubFiles(store: Self.store(), environment: [:])

    #expect(files.hubsDirectory == nil)
    #expect(files.path(forName: "basement") == nil)

  }

  @Test(arguments: ["../env", "../../etc/passwd", "a/b", "/etc/passwd", ".", "..", "", "Basement", "a.b", "~"])
  func neverNamesAFileOutsideTheDirectory(name: String) {

    #expect(HubFiles(store: Self.store(), environment: Self.home).path(forName: name) == nil)

  }

  @Test(arguments: ["../env", "../../etc/passwd", "a/b", "/etc/passwd", ".", ".."])
  func refusesATraversalNameWhenLoading(name: String) {

    #expect(throws: ArgumentError.invalidHubName(name)) {

      try Self.load(hubName: name)

    }

  }

  // MARK: - Existing setups

  @Test func readsTheDefaultFileWhenNothingNamesAHub() throws {

    let environment = try Self.load()

    #expect(environment["INSTEON_HUB_PASSWORD"] == "standard-secret")
    #expect(environment["INSTEON_HUB_HOST"] == "192.168.1.20")

  }

  @Test func needsNoDefaultFile() throws {

    let environment = try Self.load(store: FakeHubFiles())

    #expect(environment == Self.home)

  }

  @Test func letsTheEnvironmentWinOverTheFile() throws {

    let environment = try Self.load(environment: Self.home.merging(["INSTEON_HUB_PASSWORD": "from-the-shell"]) { $1 })

    #expect(environment["INSTEON_HUB_PASSWORD"] == "from-the-shell")
    #expect(environment["INSTEON_HUB_USERNAME"] == "standard-user")

  }

  @Test func readsNothingWithoutAHomeOrAnExplicitFile() throws {

    #expect(try Self.load(environment: [:]) == [:])

  }

  // MARK: - Naming a Hub

  @Test func readsTheNamedFileInPlaceOfTheDefault() throws {

    let environment = try Self.load(hubName: "basement")

    #expect(environment["INSTEON_HUB_USERNAME"] == "basement-user")
    #expect(environment["INSTEON_HUB_HOST"] == "192.168.1.30")
    #expect(environment["INSTEON_HUB_PORT"] == "8080")

  }

  @Test func leavesTheDefaultFilesValuesOutWhenAHubIsNamed() throws {

    let environment = try Self.load(hubName: "garage")

    #expect(environment["INSTEON_HUB_HOST"] == nil)
    #expect(environment["INSTEON_HUB_USERNAME"] == "garage-user")

  }

  @Test func letsTheEnvironmentWinOverANamedFile() throws {

    let environment = try Self.load(hubName: "basement", environment: Self.home.merging(["INSTEON_HUB_PORT": "9999"]) { $1 })

    #expect(environment["INSTEON_HUB_PORT"] == "9999")

  }

  @Test func aNamedFileNeedsNoAddressWhenItSetsOne() throws {

    let environment = try Self.load(hubName: "basement")

    #expect(try ModemTarget.resolve(hub: nil, serialPath: nil, environment: environment) == .hub(host: "192.168.1.30", port: 8080))

  }

  @Test func anExplicitAddressWinsOverTheHostInAFile() throws {

    let environment = try Self.load(hubName: "basement")

    #expect(try ModemTarget.resolve(hub: "192.168.1.99", serialPath: nil, environment: environment) == .hub(host: "192.168.1.99", port: 8080))

  }

  // MARK: - Precedence

  @Test func anEnvFileWinsOverANameAndTheVariable() throws {

    let store = Self.store(["/elsewhere/custom.env": "INSTEON_HUB_USERNAME=custom-user\n"])
    let environment = try Self.load(
      explicitPath: "/elsewhere/custom.env",
      hubName: "basement",
      environment: Self.home.merging(["INSTEON_HUB": "garage"]) { $1 },
      store: store
    )

    #expect(environment["INSTEON_HUB_USERNAME"] == "custom-user")
    #expect(environment["INSTEON_HUB_HOST"] == nil)

  }

  @Test func aMissingEnvFileIsAnErrorEvenWhenAHubIsNamed() {

    #expect(throws: EnvironmentFileError.notFound(path: "/elsewhere/missing.env")) {

      try Self.load(explicitPath: "/elsewhere/missing.env", hubName: "basement")

    }

  }

  @Test func aNameWinsOverTheVariable() throws {

    let environment = try Self.load(hubName: "basement", environment: Self.home.merging(["INSTEON_HUB": "garage"]) { $1 })

    #expect(environment["INSTEON_HUB_USERNAME"] == "basement-user")

  }

  @Test func theVariableWinsOverTheDefaultFile() throws {

    let environment = try Self.load(environment: Self.home.merging(["INSTEON_HUB": "garage"]) { $1 })

    #expect(environment["INSTEON_HUB_USERNAME"] == "garage-user")
    #expect(environment["INSTEON_HUB_HOST"] == nil)

  }

  @Test func anEmptyVariableNamesNoHub() throws {

    let environment = try Self.load(environment: Self.home.merging(["INSTEON_HUB": ""]) { $1 })

    #expect(environment["INSTEON_HUB_USERNAME"] == "standard-user")

  }

  @Test func theVariableStaysInTheEnvironment() throws {

    let environment = try Self.load(environment: Self.home.merging(["INSTEON_HUB": "garage"]) { $1 })

    #expect(environment["INSTEON_HUB"] == "garage")

  }

  // MARK: - Names that don't resolve

  @Test func saysWhichNamesExistAndWhereItLooked() {

    #expect(throws: ConfigurationError.unknownHub(
      name: "attic",
      path: "/home/example/.config/insteon/hubs/attic.env",
      known: ["basement", "garage"],
      source: .option
    )) {

      try Self.load(hubName: "attic")

    }

  }

  @Test func listsOnlyUsableNamesAmongTheKnownOnes() {

    let store = Self.store([
      Self.configuration + "/hubs/notes.txt": "x",
      Self.configuration + "/hubs/Upper.env": "x",
      Self.configuration + "/hubs/a.b.env": "x",
      Self.configuration + "/hubs/.env": "x"
    ])

    #expect(throws: ConfigurationError.unknownHub(
      name: "attic",
      path: "/home/example/.config/insteon/hubs/attic.env",
      known: ["basement", "garage"],
      source: .option
    )) {

      try Self.load(hubName: "attic", store: store)

    }

  }

  @Test func saysSoWhenNoHubFilesExist() {

    #expect(throws: ConfigurationError.unknownHub(
      name: "attic",
      path: "/home/example/.config/insteon/hubs/attic.env",
      known: [],
      source: .option
    )) {

      try Self.load(hubName: "attic", store: FakeHubFiles())

    }

  }

  @Test func theUnknownNameMessageNamesTheNamesAndTheFile() {

    let message = String(describing: ConfigurationError.unknownHub(
      name: "attic",
      path: "/home/example/.config/insteon/hubs/attic.env",
      known: ["basement", "garage"],
      source: .option
    ))

    #expect(message.contains("'attic'"))
    #expect(message.contains("/home/example/.config/insteon/hubs/attic.env"))
    #expect(message.contains("basement, garage"))
    #expect(!message.contains("INSTEON_HUB "))

  }

  @Test func theMessageSaysHowToCreateAFileWhenThereAreNone() {

    let message = String(describing: ConfigurationError.unknownHub(
      name: "attic",
      path: "/home/example/.config/insteon/hubs/attic.env",
      known: [],
      source: .option
    ))

    #expect(message.contains("/home/example/.config/insteon/hubs/attic.env"))
    #expect(message.contains("No Hub files"))
    #expect(message.contains("chmod 600"))

  }

  @Test func aVariableNamingAMissingFileIsAnErrorThatNamesTheFile() {

    #expect(throws: ConfigurationError.unknownHub(
      name: "attic",
      path: "/home/example/.config/insteon/hubs/attic.env",
      known: ["basement", "garage"],
      source: .variable
    )) {

      try Self.load(environment: Self.home.merging(["INSTEON_HUB": "attic"]) { $1 })

    }

  }

  @Test func theVariablesMessageNamesTheVariableAndTheFile() {

    let message = String(describing: ConfigurationError.unknownHub(
      name: "attic",
      path: "/home/example/.config/insteon/hubs/attic.env",
      known: ["basement"],
      source: .variable
    ))

    #expect(message.hasPrefix("INSTEON_HUB names the Hub 'attic'"))
    #expect(message.contains("/home/example/.config/insteon/hubs/attic.env"))

  }

  @Test func neverFallsBackToTheDefaultFileForAVariable() {

    // The default file exists and has credentials, yet a missing named file is still an error.
    #expect(throws: ConfigurationError.self) {

      try Self.load(environment: Self.home.merging(["INSTEON_HUB": "attic"]) { $1 })

    }

  }

  @Test(arguments: ["../env", "a/b", "Basement", "a.b", "/etc/passwd"])
  func refusesAVariableThatIsNotAName(value: String) {

    #expect(throws: ConfigurationError.invalidHubVariable(value)) {

      try Self.load(environment: Self.home.merging(["INSTEON_HUB": value]) { $1 })

    }

  }

  @Test func needsAHomeToFindANamedFile() {

    #expect(throws: ConfigurationError.noConfigurationDirectory) {

      try Self.load(hubName: "basement", environment: [:])

    }
    #expect(throws: ConfigurationError.noConfigurationDirectory) {

      try Self.load(environment: ["INSTEON_HUB": "basement"])

    }

  }

  // MARK: - The existing checks

  @Test func refusesANamedFileOthersCanWrite() {

    var store = Self.store()
    store.files[Self.configuration + "/hubs/basement.env"]?.mode = 0o100_660

    #expect(throws: EnvironmentFileError.refused(path: Self.configuration + "/hubs/basement.env", .writableByOthers)) {

      try Self.load(hubName: "basement", store: store)

    }

  }

  @Test func refusesANamedFileAnotherUserOwns() {

    var store = Self.store()
    store.files[Self.configuration + "/hubs/basement.env"]?.ownerID = 0

    #expect(throws: EnvironmentFileError.refused(path: Self.configuration + "/hubs/basement.env", .ownedByAnotherUser)) {

      try Self.load(hubName: "basement", store: store)

    }

  }

  @Test func refusesANamedFileThatIsNotARegularFile() {

    var store = Self.store()
    store.files[Self.configuration + "/hubs/basement.env"]?.mode = 0o040_700

    #expect(throws: EnvironmentFileError.refused(path: Self.configuration + "/hubs/basement.env", .notRegularFile)) {

      try Self.load(hubName: "basement", store: store)

    }

  }

  @Test func warnsWhenOthersCanReadANamedFile() throws {

    var store = Self.store()
    store.files[Self.configuration + "/hubs/basement.env"]?.mode = 0o100_644

    var warnings: [String] = []
    let environment = try Self.load(hubName: "basement", store: store, warnings: &warnings)

    #expect(environment["INSTEON_HUB_USERNAME"] == "basement-user")
    #expect(warnings == ["others can read /home/example/.config/insteon/hubs/basement.env"])

  }

  @Test func reportsANamedFileThatCantBeOpenedAsUnreadable() {

    var store = Self.store()
    store.unopenable = [Self.configuration + "/hubs/basement.env"]

    #expect(throws: EnvironmentFileError.unreadable(path: Self.configuration + "/hubs/basement.env")) {

      try Self.load(hubName: "basement", store: store)

    }

  }

  @Test func reportsAMalformedLine() {

    let store = Self.store([Self.configuration + "/hubs/basement.env": "INSTEON_HUB_HOST=192.168.1.30\nnot a variable\n"])

    #expect(throws: DotEnvError.malformedLine(2)) {

      try Self.load(hubName: "basement", store: store)

    }

  }

}
