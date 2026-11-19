import ArgumentParser
import Foundation
import RepoCheckSupport
import RepoChecks

@main
struct RepoCheckCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "repo-check",
    abstract: "Checks the repository against its rules.",
    discussion: "Each check exits with status 0 if it finds nothing and 1 if it finds a problem.",
    subcommands: [WorkflowsCommand.self, TermsCommand.self, CLIThinCommand.self, ConcurrencyCommand.self, CredentialsCommand.self, DeviceNeutralCommand.self, TimeLimitsCommand.self, PublicAPICommand.self, AllowListGrowthCommand.self]
  )
}

/// The options every check takes.
struct RootOptions: ParsableArguments {
  @Option(help: "The repository. The current directory by default.")
  var root: String?

  var rootURL: URL {
    URL(fileURLWithPath: root ?? FileManager.default.currentDirectoryPath, isDirectory: true)
  }
}

extension RepoCheck {
  /// Runs the check on standard output and exits with its status if it didn't pass.
  func runAsCommand(_ options: RootOptions) throws {
    let console = StandardConsole()
    let status: CheckStatus
    do {
      status = try run(in: options.rootURL, console: console)
    } catch let failure as CheckFailure {
      console.writeError(failure.message)
      throw ExitCode.failure
    }
    if status != .passed {
      throw ExitCode(status.rawValue)
    }
  }
}

struct WorkflowsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "workflows",
    abstract: "Checks that the workflows pin their actions and images and limit their jobs."
  )

  @OptionGroup var options: RootOptions

  func run() throws {
    try WorkflowsCheck().runAsCommand(options)
  }
}

struct TermsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "terms",
    abstract: "Checks the docs and comments for the terms CONVENTIONS.md rules out."
  )

  @OptionGroup var options: RootOptions

  func run() throws {
    try TermsCheck().runAsCommand(options)
  }
}

/// The options of a check that keeps an allow-list.
struct AllowListOptions: ParsableArguments {
  @Option(help: "The known lines. Scripts/ under the repository by default.")
  var allowlist: String?

  @Flag(help: "Write the allow-list from the sources.")
  var update = false
}

struct CLIThinCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "cli-thin",
    abstract: "Checks that the insteon command leaves device behavior to the libraries."
  )

  @OptionGroup var options: RootOptions
  @OptionGroup var allowList: AllowListOptions

  @Option(name: .customLong("sources"), help: "A directory of sources to check; may be given more than once.")
  var sources: [String] = []

  func run() throws {
    var check = CLIThinCheck(update: allowList.update)
    check.sources = sources.isEmpty ? nil : sources.map { URL(fileURLWithPath: $0, isDirectory: true) }
    check.allowlist = allowList.allowlist.map { URL(fileURLWithPath: $0) }
    try check.runAsCommand(options)
  }
}

struct ConcurrencyCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "concurrency",
    abstract: "Checks the libraries for unstructured tasks, unchecked Sendable types and real clocks."
  )

  @OptionGroup var options: RootOptions
  @OptionGroup var allowList: AllowListOptions

  @Option(help: "The packages directory, each package with Sources. Packages/ under the repository by default.")
  var packages: String?

  func run() throws {
    try ConcurrencyCheck(
      packages: packages.map { URL(fileURLWithPath: $0, isDirectory: true) },
      allowlist: allowList.allowlist.map { URL(fileURLWithPath: $0) },
      update: allowList.update
    ).runAsCommand(options)
  }
}

struct CredentialsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "credentials",
    abstract: "Checks that no credential is written into a string by interpolation."
  )

  @OptionGroup var options: RootOptions
  @OptionGroup var allowList: AllowListOptions

  @Option(help: "The packages directory, each package with Sources. Packages/ under the repository by default.")
  var packages: String?

  func run() throws {
    try CredentialsCheck(
      packages: packages.map { URL(fileURLWithPath: $0, isDirectory: true) },
      allowlist: allowList.allowlist.map { URL(fileURLWithPath: $0) },
      update: allowList.update
    ).runAsCommand(options)
  }
}

struct DeviceNeutralCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "device-neutral",
    abstract: "Checks that the core, the command and the in-memory modem name no real device."
  )

  @OptionGroup var options: RootOptions
  @OptionGroup var allowList: AllowListOptions

  @Option(help: "The catalog the words come from. The bundled one by default.")
  var catalog: String?

  func run() throws {
    try DeviceNeutralCheck(
      catalog: catalog.map { URL(fileURLWithPath: $0) },
      allowlist: allowList.allowlist.map { URL(fileURLWithPath: $0) },
      update: allowList.update
    ).runAsCommand(options)
  }
}

struct TimeLimitsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "time-limits",
    abstract: "Checks that every async test has a time limit."
  )

  @OptionGroup var options: RootOptions

  @Option(name: .customLong("tests"), help: "A directory of tests to check; may be given more than once.")
  var tests: [String] = []

  func run() throws {
    var check = TimeLimitsCheck()
    check.roots = tests.isEmpty ? nil : tests.map { URL(fileURLWithPath: $0, isDirectory: true) }
    try check.runAsCommand(options)
  }
}

struct PublicAPICommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "public-api",
    abstract: "Checks that InsteonCore's public API matches its list."
  )

  @OptionGroup var options: RootOptions

  @Option(help: "InsteonCore's sources. Packages/InsteonCore/Sources/InsteonCore under the repository by default.")
  var sources: String?

  @Option(name: .customLong("list"), help: "The committed list. Scripts/insteoncore-public-api.txt by default.")
  var list: String?

  @Flag(help: "Write the list from the sources.")
  var update = false

  func run() throws {
    try PublicAPICheck(
      sources: sources.map { URL(fileURLWithPath: $0, isDirectory: true) },
      list: list.map { URL(fileURLWithPath: $0) },
      update: update
    ).runAsCommand(options)
  }
}

struct AllowListGrowthCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "allowlist-growth",
    abstract: "Checks that no allow-list gained an entry compared with the base."
  )

  @OptionGroup var options: RootOptions

  @Option(help: "The ref to compare with, such as origin/main.")
  var base: String

  func run() throws {
    try AllowListGrowthCheck(base: base).runAsCommand(options)
  }
}
