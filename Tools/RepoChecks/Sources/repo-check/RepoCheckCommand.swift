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
    subcommands: [WorkflowsCommand.self]
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
    let status = try run(in: options.rootURL, console: StandardConsole())
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
