import Testing
import InsteonCLISupport
import InsteonCore

struct ExitStatusTests {

  @Test func aCommandLineOrConfigurationThatCantBeUsedIsAUsageError() {

    #expect(ExitStatus.status(for: ArgumentError.missingAddress) == ExitStatus.usage)
    #expect(ExitStatus.status(for: ConfigurationError.serialUnavailable) == ExitStatus.usage)
    #expect(ExitStatus.status(for: DotEnvError.malformedLine(3)) == ExitStatus.usage)
    #expect(ExitStatus.status(for: EnvironmentFileError.notFound(path: "/example/.env")) == ExitStatus.usage)

  }

  @Test func anInterruptionHasTheStatusOfControlC() {

    #expect(ExitStatus.status(for: CancellationError()) == ExitStatus.interrupted)

  }

  @Test func anyOtherErrorIsAFailure() {

    #expect(ExitStatus.status(for: CommandFailure(description: "Example.")) == ExitStatus.failure)
    #expect(ExitStatus.status(for: HubAddressRefused(host: "203.0.113.5")) == ExitStatus.failure)

  }

}
