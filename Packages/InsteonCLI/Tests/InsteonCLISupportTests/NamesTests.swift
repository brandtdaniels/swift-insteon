import Testing
import InsteonCLISupport
import InsteonCore
import InsteonHubClient

struct NamesTests {

  // MARK: - Errors

  @Test func givesACommandFailureItsOwnMessage() {

    #expect(Names.message(for: CommandFailure(description: "The example went wrong.")) == "The example went wrong.")

  }

  @Test func callsCancellationAnInterruption() {

    #expect(Names.message(for: CancellationError()) == "Interrupted.")

  }

  @Test func givesACommandLineErrorItsDescription() {

    let error = ArgumentError.missingAddress

    #expect(Names.message(for: error) == error.description)

  }

  @Test func saysWhereToSetTheHubsCredentialsWhenTheHubRejectsThem() {

    let rejected: any Error = HubError.unexpectedStatus(401)

    #expect(
      Names.message(for: rejected)
        == "The Hub rejected its user name and password (HTTP 401). Check INSTEON_HUB_USERNAME and INSTEON_HUB_PASSWORD."
    )

  }

  @Test func describesAnotherHubErrorWithoutTheCredentialsHint() {

    #expect(Names.message(for: HubError.unexpectedStatus(500)) == "The Hub answered with HTTP status 500.")

  }

  // MARK: - Values

  @Test func namesAnUnknownEngineAndRole() {

    #expect(Names.engine(nil) == "unknown")
    #expect(Names.mode(nil) == "unknown")

  }

}
