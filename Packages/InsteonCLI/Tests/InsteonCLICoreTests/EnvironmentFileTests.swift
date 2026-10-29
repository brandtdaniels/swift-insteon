import Testing
import InsteonCLICore

struct EnvironmentFileTests {

  let user = 501

  // MARK: - Path

  @Test func usesXDGConfigHomeFirst() {

    let environment = ["XDG_CONFIG_HOME": "/home/example/.xdg", "HOME": "/home/example"]

    #expect(EnvironmentFile.path(explicit: nil, environment: environment) == "/home/example/.xdg/insteon/env")
    #expect(EnvironmentFile.path(explicit: nil, environment: ["XDG_CONFIG_HOME": "/home/example/.xdg/"]) == "/home/example/.xdg/insteon/env")

  }

  @Test func fallsBackToTheHomeDirectory() {

    #expect(EnvironmentFile.path(explicit: nil, environment: ["HOME": "/home/example"]) == "/home/example/.config/insteon/env")

    // The XDG Base Directory Specification ignores a relative or empty XDG_CONFIG_HOME.
    #expect(
      EnvironmentFile.path(explicit: nil, environment: ["XDG_CONFIG_HOME": "relative", "HOME": "/home/example"])
        == "/home/example/.config/insteon/env"
    )
    #expect(
      EnvironmentFile.path(explicit: nil, environment: ["XDG_CONFIG_HOME": "", "HOME": "/home/example"])
        == "/home/example/.config/insteon/env"
    )

  }

  @Test func hasNoDefaultWithoutAHomeDirectory() {

    #expect(EnvironmentFile.path(explicit: nil, environment: [:]) == nil)
    #expect(EnvironmentFile.path(explicit: nil, environment: ["HOME": ""]) == nil)

  }

  @Test func prefersTheFileTheCommandLineNames() {

    let environment = ["XDG_CONFIG_HOME": "/home/example/.xdg", "HOME": "/home/example"]

    #expect(EnvironmentFile.path(explicit: "/home/example/hub.env", environment: environment) == "/home/example/hub.env")
    #expect(EnvironmentFile.path(explicit: "hub.env", environment: [:]) == "hub.env")

  }

  // MARK: - Verdict

  @Test func readsAFileOnlyItsOwnerCanRead() {

    #expect(EnvironmentFile.verdict(mode: 0o100600, ownerID: user, currentUserID: user) == .read)
    #expect(EnvironmentFile.verdict(mode: 0o100400, ownerID: user, currentUserID: user) == .read)

  }

  @Test func warnsAboutAFileOthersCanRead() {

    #expect(EnvironmentFile.verdict(mode: 0o100640, ownerID: user, currentUserID: user) == .readWithWarning)
    #expect(EnvironmentFile.verdict(mode: 0o100644, ownerID: user, currentUserID: user) == .readWithWarning)
    #expect(EnvironmentFile.verdict(mode: 0o100604, ownerID: user, currentUserID: user) == .readWithWarning)

  }

  @Test func refusesAFileOthersCanWrite() {

    #expect(EnvironmentFile.verdict(mode: 0o100620, ownerID: user, currentUserID: user) == .refuse(.writableByOthers))
    #expect(EnvironmentFile.verdict(mode: 0o100602, ownerID: user, currentUserID: user) == .refuse(.writableByOthers))
    #expect(EnvironmentFile.verdict(mode: 0o100666, ownerID: user, currentUserID: user) == .refuse(.writableByOthers))

  }

  @Test func refusesAnotherUsersFile() {

    #expect(EnvironmentFile.verdict(mode: 0o100600, ownerID: 502, currentUserID: user) == .refuse(.ownedByAnotherUser))
    #expect(EnvironmentFile.verdict(mode: 0o100600, ownerID: 0, currentUserID: user) == .refuse(.ownedByAnotherUser))

  }

  @Test func refusesSomethingOtherThanARegularFile() {

    #expect(EnvironmentFile.verdict(mode: 0o040700, ownerID: user, currentUserID: user) == .refuse(.notRegularFile))
    #expect(EnvironmentFile.verdict(mode: 0o010600, ownerID: user, currentUserID: user) == .refuse(.notRegularFile))

  }

  // MARK: - Messages

  @Test func explainsRefusalsWithChmod() {

    let path = "/home/example/.config/insteon/env"
    let writable = EnvironmentFileError.refused(path: path, .writableByOthers)
    let errors: [EnvironmentFileError] = [
      .notFound(path: path),
      .unreadable(path: path),
      .refused(path: path, .notRegularFile),
      .refused(path: path, .ownedByAnotherUser),
      writable
    ]

    for error in errors {

      #expect(error.description.contains(path))
      #expect(!error.description.contains("\n"))

    }

    #expect(writable.description.contains("chmod 600"))

  }

}
