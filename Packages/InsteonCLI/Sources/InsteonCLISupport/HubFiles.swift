/// Chooses the environment file a command reads, among the default file, the file `--env-file`
/// names, and the Hub files in the `hubs` directory beside it.
///
/// The default file is `$XDG_CONFIG_HOME/insteon/env`, or `~/.config/insteon/env`. A Hub file
/// is `hubs/NAME.env` in the same directory, written in the same form, held to the same checks
/// of type, owner and permissions, and never read from the current directory. It can set
/// `INSTEON_HUB_HOST` and `INSTEON_HUB_PORT` as well as the Hub's credentials, so naming a Hub
/// needs no address.
///
/// The file is the first of these that applies:
/// 1. the file `--env-file` names,
/// 2. the Hub file `--hub NAME` names,
/// 3. the Hub file the `INSTEON_HUB` environment variable names,
/// 4. the default file.
///
/// ```swift
/// let files = HubFiles(store: LocalHubFiles(), environment: ProcessInfo.processInfo.environment)
/// let environment = try files.load(explicitPath: nil, hubName: "basement", warn: { print($0) })
/// ```
public struct HubFiles: Sendable {

  /// The name of the variable that names a Hub file when `--hub` doesn't: `INSTEON_HUB`.
  public static let variableName = "INSTEON_HUB"

  /// The extension of a Hub file, with its dot.
  public static let fileExtension = ".env"

  /// The store the files are read from.
  public let store: any HubFileStore

  /// The process's environment, which gives the variables that choose and locate the files.
  public let environment: [String: String]

  /// Creates the chooser.
  ///
  /// - Parameters:
  ///   - store: Where the files are.
  ///   - environment: The process's environment.
  public init(store: any HubFileStore, environment: [String: String]) {

    self.store = store
    self.environment = environment

  }

  /// The directory of Hub files: `hubs` in the directory of the default file, or `nil` when
  /// neither `XDG_CONFIG_HOME` nor `HOME` is set.
  public var hubsDirectory: String? {

    EnvironmentFile.defaultPath(environment: environment).map { (defaultPath: String) -> String in

      String(defaultPath.dropLast("env".count)) + "hubs"

    }

  }

  /// The path of the Hub file a name gives.
  ///
  /// - Parameter name: A Hub's name.
  /// - Returns: The path, or `nil` if the name isn't a valid ``HubName`` or there's no
  ///   directory to look in. A name can't reach outside the directory of Hub files.
  public func path(forName name: String) -> String? {

    guard HubName.isValid(name), let directory = hubsDirectory else {

      return nil

    }

    return directory + "/" + name + Self.fileExtension

  }

  /// The names of the Hub files in the directory, sorted: those that end in `.env` and whose
  /// stem is a valid ``HubName``.
  public var names: [String] {

    guard let directory = hubsDirectory, let entries = store.fileNames(inDirectory: directory) else {

      return []

    }

    return entries.compactMap { (entry: String) -> String? in

      guard entry.hasSuffix(Self.fileExtension) else {

        return nil

      }

      let name = String(entry.dropLast(Self.fileExtension.count))

      return HubName.isValid(name) ? name : nil

    }.sorted()

  }

  /// The name `INSTEON_HUB` gives, if it's set and not empty.
  public var variableHubName: String? {

    guard let value = environment[Self.variableName], !value.isEmpty else {

      return nil

    }

    return value

  }

  /// The process's environment, with the variables of the chosen file merged in. A variable
  /// set in the environment wins over the file.
  ///
  /// The default file is optional. A file named with `--env-file`, `--hub` or `INSTEON_HUB` is
  /// not: one that doesn't exist is an error, and the command never falls back to the default
  /// file in its place.
  ///
  /// - Parameters:
  ///   - explicitPath: The path given with `--env-file`, if any.
  ///   - hubName: The name given with `--hub`, if any. Ignored when `explicitPath` is given.
  ///   - warn: Shows a warning, such as that others can read the file.
  /// - Returns: The environment, with the file's variables added.
  /// - Throws: ``ArgumentError/invalidHubName(_:)`` if `hubName` isn't a name,
  ///   ``ConfigurationError`` if `INSTEON_HUB` isn't a name or a named file doesn't exist,
  ///   ``EnvironmentFileError`` if a file can't or mustn't be read, or ``DotEnvError`` if it
  ///   has a malformed line.
  public func load(explicitPath: String?, hubName: String?, warn: (String) -> Void) throws -> [String: String] {

    guard let (path, required) = try chosenFile(explicitPath: explicitPath, hubName: hubName) else {

      return environment

    }

    guard store.exists(atPath: path) else {

      guard required else {

        return environment

      }

      throw missing(path: path, explicitPath: explicitPath, hubName: hubName)

    }

    let contents: String = try store.read(at: path, warn: warn)

    return try DotEnv.merging(DotEnv.parse(contents), into: environment)

  }

  // MARK: - Choosing

  private enum Choice {

    case explicit

    case option(String)

    case variable(String)

    case standard

  }

  private func choice(explicitPath: String?, hubName: String?) throws -> Choice {

    if explicitPath != nil {

      return .explicit

    }

    if let hubName {

      guard HubName.isValid(hubName) else {

        throw ArgumentError.invalidHubName(hubName)

      }

      return .option(hubName)

    }

    if let value = variableHubName {

      guard HubName.isValid(value) else {

        throw ConfigurationError.invalidHubVariable(value)

      }

      return .variable(value)

    }

    return .standard

  }

  /// The path to read and whether it must exist, or `nil` when there's nothing to read.
  private func chosenFile(explicitPath: String?, hubName: String?) throws -> (path: String, required: Bool)? {

    switch try choice(explicitPath: explicitPath, hubName: hubName) {
    case .explicit:
      return explicitPath.map { (path: $0, required: true) }
    case let .option(name), let .variable(name):
      guard let path = path(forName: name) else {

        throw ConfigurationError.noConfigurationDirectory

      }

      return (path, true)
    case .standard:
      return EnvironmentFile.defaultPath(environment: environment).map { (path: $0, required: false) }
    }

  }

  private func missing(path: String, explicitPath: String?, hubName: String?) -> any Error {

    if explicitPath != nil {

      return EnvironmentFileError.notFound(path: path)

    }

    let isOption = hubName != nil
    let name = hubName ?? variableHubName ?? ""

    return ConfigurationError.unknownHub(name: name, path: path, known: names, source: isOption ? .option : .variable)

  }

}
