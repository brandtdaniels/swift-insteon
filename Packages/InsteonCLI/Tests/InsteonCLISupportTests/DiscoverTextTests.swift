import Testing
import InsteonCLISupport

/// What `insteon discover` prints for the Hubs it found: invented addresses and IDs.
struct DiscoverTextTests {

  static let directory = "/home/example/.config/insteon/hubs"
  static let home = "/home/example"

  static let hubPro = DiscoveredHub(product: "Hub Pro 2243", host: "192.168.1.43", port: 80, insteonID: "4D.5E.6F", foundBy: ["Insteon staging"], isHubPro: true)
  static let hub2 = DiscoveredHub(product: "Hub 2245", host: "192.168.1.20", port: 25_105, insteonID: "1A.2B.3C", foundBy: ["Local network"], isHubPro: false)

  static let loginParagraph = [
    "A Hub Pro takes no login. A Hub 2 or Hub 1 also needs INSTEON_HUB_USERNAME and INSTEON_HUB_PASSWORD",
    "(its login, from its label or the Insteon app); never type them on the command line.",
  ]
  static let hubProSentence = "A Hub Pro's devices are linked with its Set buttons; insteon reads and controls them."

  func lines(_ hubs: [DiscoveredHub], directory: String? = directory, home: String? = home, saved: [SavedHubFile] = []) -> [String] {

    DiscoverText.lines(for: hubs, directory: directory, home: home, saved: saved)

  }

  @Test func showsOneHubProWithItsFileAndNoLogin() {

    #expect(
      lines([Self.hubPro]) == [
        "Found 1 Hub:",
        "",
        "  PRODUCT       ADDRESS          INSTEON ID  FOUND BY",
        "  Hub Pro 2243  192.168.1.43:80  4D.5E.6F    Insteon staging",
        "",
        "To use a Hub by name, save its settings in a file readable only by you:",
        "",
        "  hubpro-5e6f   ~/.config/insteon/hubs/hubpro-5e6f.env",
        "    INSTEON_HUB_HOST=192.168.1.43",
        "    then: insteon --hub hubpro-5e6f info",
        "",
        Self.hubProSentence,
      ] + Self.loginParagraph
    )

  }

  @Test func showsOneHub2WithItsLoginPlaceholdersAndChmod() {

    #expect(
      lines([Self.hub2]) == [
        "Found 1 Hub:",
        "",
        "  PRODUCT   ADDRESS             INSTEON ID  FOUND BY",
        "  Hub 2245  192.168.1.20:25105  1A.2B.3C    Local network",
        "",
        "To use a Hub by name, save its settings in a file readable only by you:",
        "",
        "  hub-2b3c   ~/.config/insteon/hubs/hub-2b3c.env",
        "    INSTEON_HUB_HOST=192.168.1.20",
        "    INSTEON_HUB_USERNAME=<the Hub's username>",
        "    INSTEON_HUB_PASSWORD=<the Hub's password>",
        "    then: chmod 600 ~/.config/insteon/hubs/hub-2b3c.env",
        "    then: insteon --hub hub-2b3c info",
        "",
      ] + Self.loginParagraph
    )

  }

  @Test func showsBothKindsInOneTableWithAFileBlockEach() {

    #expect(
      lines([Self.hub2, Self.hubPro]) == [
        "Found 2 Hubs:",
        "",
        "  PRODUCT       ADDRESS             INSTEON ID  FOUND BY",
        "  Hub 2245      192.168.1.20:25105  1A.2B.3C    Local network",
        "  Hub Pro 2243  192.168.1.43:80     4D.5E.6F    Insteon staging",
        "",
        "To use a Hub by name, save its settings in a file readable only by you:",
        "",
        "  hub-2b3c      ~/.config/insteon/hubs/hub-2b3c.env",
        "    INSTEON_HUB_HOST=192.168.1.20",
        "    INSTEON_HUB_USERNAME=<the Hub's username>",
        "    INSTEON_HUB_PASSWORD=<the Hub's password>",
        "    then: chmod 600 ~/.config/insteon/hubs/hub-2b3c.env",
        "    then: insteon --hub hub-2b3c info",
        "",
        "  hubpro-5e6f   ~/.config/insteon/hubs/hubpro-5e6f.env",
        "    INSTEON_HUB_HOST=192.168.1.43",
        "    then: insteon --hub hubpro-5e6f info",
        "",
        Self.hubProSentence,
      ] + Self.loginParagraph
    )

  }

  @Test func sayssAHubIsAlreadySavedInsteadOfHowToSaveIt() {

    let saved = [SavedHubFile(name: "attic", address: "192.168.1.20")]

    #expect(
      lines([Self.hub2], saved: saved) == [
        "Found 1 Hub:",
        "",
        "  PRODUCT   ADDRESS             INSTEON ID  FOUND BY",
        "  Hub 2245  192.168.1.20:25105  1A.2B.3C    Local network",
        "",
        "  192.168.1.20:25105  already saved as attic",
        "    then: insteon --hub attic info",
      ]
    )

  }

  @Test func matchesASavedFileByHostAndPortOrByHostAlone() {

    let byPort = lines([Self.hubPro], saved: [SavedHubFile(name: "pro", address: "192.168.1.43:80")])
    let otherPort = lines([Self.hubPro], saved: [SavedHubFile(name: "pro", address: "192.168.1.43:443")])

    #expect(byPort.contains("  192.168.1.43:80  already saved as pro"))
    #expect(!otherPort.contains { $0.contains("already saved") })

  }

  @Test func showsHowToSaveOnlyTheHubsNotSaved() {

    let output = lines([Self.hub2, Self.hubPro], saved: [SavedHubFile(name: "attic", address: "192.168.1.20")])

    #expect(output.contains("  192.168.1.20:25105  already saved as attic"))
    #expect(output.contains("To use a Hub by name, save its settings in a file readable only by you:"))
    #expect(output.contains("  hubpro-5e6f   ~/.config/insteon/hubs/hubpro-5e6f.env"))
    #expect(!output.contains { $0.contains("hub-2b3c") })
    #expect(output.contains(Self.hubProSentence))

  }

  @Test func leavesOutTheHubProSentenceWhenNoHubProIsListed() {

    #expect(!lines([Self.hub2]).contains(Self.hubProSentence))

  }

  @Test func leavesOutAColumnNoHubHas() {

    let bare = DiscoveredHub(product: nil, host: "192.168.1.20", port: 25_105, insteonID: nil, foundBy: ["Local network"], isHubPro: false)

    #expect(Array(lines([bare])[2...3]) == ["  ADDRESS             FOUND BY", "  192.168.1.20:25105  Local network"])

  }

  @Test func showsADashWhereOnlySomeHubsHaveAValue() {

    let unknown = DiscoveredHub(product: nil, host: "192.168.1.21", port: 25_105, insteonID: nil, foundBy: ["Local network"], isHubPro: false)
    let table = Array(lines([Self.hub2, unknown])[2...4])

    #expect(
      table == [
        "  PRODUCT   ADDRESS             INSTEON ID  FOUND BY",
        "  Hub 2245  192.168.1.20:25105  1A.2B.3C    Local network",
        "  -         192.168.1.21:25105  -           Local network",
      ]
    )

  }

  @Test func addsThePortOfAHubOnAnotherPort() {

    let other = DiscoveredHub(product: "Hub 2245", host: "192.168.1.20", port: 25_106, insteonID: "1A.2B.3C", foundBy: ["Local network"], isHubPro: false)

    #expect(lines([other]).contains("    INSTEON_HUB_PORT=25106"))
    #expect(!lines([Self.hub2]).contains { $0.contains("INSTEON_HUB_PORT") })
    #expect(!lines([Self.hubPro]).contains { $0.contains("INSTEON_HUB_PORT") })

  }

  @Test func showsNothingWhenNoHubIsFound() {

    #expect(lines([]).isEmpty)

  }

  @Test func showsTheRealDirectoryWhenItIsNotUnderTheHomeDirectory() {

    #expect(lines([Self.hubPro], directory: "/etc/insteon/hubs").contains("  hubpro-5e6f   /etc/insteon/hubs/hubpro-5e6f.env"))
    #expect(lines([Self.hubPro], home: nil).contains("  hubpro-5e6f   /home/example/.config/insteon/hubs/hubpro-5e6f.env"))
    #expect(lines([Self.hubPro], home: "/home/exam").contains("  hubpro-5e6f   /home/example/.config/insteon/hubs/hubpro-5e6f.env"))
    #expect(lines([Self.hubPro], directory: nil).contains("  hubpro-5e6f   hubpro-5e6f.env"))

  }

  @Test func keepsEveryLineWithinOneHundredCharacters() {

    let deep = "/mnt/" + String(repeating: "a-long-directory-name/", count: 3) + "hubs"
    let output = lines([Self.hub2, Self.hubPro, Self.hub2], directory: deep, home: "/home/example")

    #expect(output.allSatisfy { $0.count <= 100 })
    #expect(output.contains("  hub-2b3c"))
    #expect(output.contains("    \(deep)/hub-2b3c.env"))
    #expect(output.contains("    then: chmod 600"))
    #expect(output.contains("      \(deep)/hub-2b3c.env"))

  }

  @Test func namesEachHubDifferentlyWhenTheirIDsEndTheSame() {

    let output = lines([Self.hub2, Self.hub2])

    #expect(output.contains { $0.hasPrefix("  hub-2b3c ") })
    #expect(output.contains { $0.hasPrefix("  hub-2b3c-2 ") })

  }

}
