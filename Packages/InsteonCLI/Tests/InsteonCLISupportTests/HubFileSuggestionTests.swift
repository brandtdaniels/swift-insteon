import Testing
import InsteonCLISupport

/// The file name and command `insteon discover` offers for each Hub it lists.
struct HubFileSuggestionTests {

  static func source(_ isHubPro: Bool = false, id: String? = nil, host: String = "192.168.1.20", port: Int = 25_105) -> HubFileSuggestion.Source {

    HubFileSuggestion.Source(isHubPro: isHubPro, insteonID: id, host: host, port: port)

  }

  @Test func namesAHubByItsTypeAndTheEndOfItsInsteonID() {

    let suggestions = HubFileSuggestion.suggestions(for: [Self.source(id: "1A.2B.3C"), Self.source(true, id: "4D.5E.6F")])

    #expect(suggestions.map(\.name) == ["hub-2b3c", "hubpro-5e6f"])
    #expect(suggestions.map(\.fileName) == ["hub-2b3c.env", "hubpro-5e6f.env"])
    #expect(suggestions.map(\.command) == ["insteon --hub hub-2b3c info", "insteon --hub hubpro-5e6f info"])

  }

  @Test func fallsBackToTheEndOfTheAddressWithoutAnInsteonID() {

    let suggestions = HubFileSuggestion.suggestions(for: [Self.source(host: "192.168.1.78"), Self.source(true, host: "10.0.0.43")])

    #expect(suggestions.map(\.name) == ["hub-78", "hubpro-43"])

  }

  @Test func usesJustTheTypeWhenThereIsNothingToTellHubsApart() {

    #expect(HubFileSuggestion.suggestions(for: [Self.source(host: "hub.example")]).map(\.name) == ["hub"])

  }

  @Test func keepsEveryNameUnique() {

    let suggestions = HubFileSuggestion.suggestions(for: [
      Self.source(id: "1A.2B.3C"),
      Self.source(id: "FF.2B.3C"),
      Self.source(id: "11.22.33", host: "192.168.1.5"),
      Self.source(host: "192.168.2.5")
    ])

    #expect(suggestions.map(\.name) == ["hub-2b3c", "hub-2b3c-2", "hub-2233", "hub-5"])
    #expect(Set(suggestions.map(\.name)).count == suggestions.count)

  }

  @Test func everyNameIsOneThatHubAcceptsAndFits() {

    let suggestions = HubFileSuggestion.suggestions(for: [
      Self.source(id: "1A.2B.3C"), Self.source(true, id: "ZZ"), Self.source(host: "::1"), Self.source(id: "../../x"), Self.source(host: "")
    ])

    #expect(suggestions.count == 5)

    for suggestion in suggestions {

      #expect(HubName.isValid(suggestion.name))

    }

  }

}
