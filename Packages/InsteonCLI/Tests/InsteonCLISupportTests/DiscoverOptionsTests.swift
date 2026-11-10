import Testing
import InsteonCLISupport

struct DiscoverOptionsTests {

  @Test func refusesToSendThePasswordToEachHubWithoutATerminalToAsk() {

    let options = DiscoverOptions(identifiesHubs: true)

    #expect(
      throws: CommandFailure(
        description: "'--identify' sends the Hub's password, and there's no terminal to ask before sending it to each Hub found. "
          + "Name the one Hub to send it to with '--identify HOST[:PORT]'."
      )
    ) {

      try options.checkIdentifying(readsFromTerminal: false)

    }

  }

  @Test func sendsThePasswordToANamedHubOrAfterAskingAtATerminal() throws {

    try DiscoverOptions(identifiesHubs: true, identifyTarget: HubAddress(host: "192.168.0.20")).checkIdentifying(readsFromTerminal: false)
    try DiscoverOptions(identifiesHubs: true).checkIdentifying(readsFromTerminal: true)
    try DiscoverOptions().checkIdentifying(readsFromTerminal: false)

  }

}
