/// The Hub files `insteon hubs` lists: the default file, and each file in the directory of Hub
/// files, with the address each sets and what keeps a file from being used.
///
/// A listing holds a Hub's address and port, never its user name or password.
public struct HubListing: Hashable, Sendable {

  /// One file in the listing.
  public struct Entry: Hashable, Sendable {

    /// The Hub's name, or `nil` for the default file.
    public var name: String?

    /// The file's path.
    public var path: String

    /// Whether a command that names no Hub reads this file.
    public var isDefault: Bool

    /// The address the file sets, as `HOST` or `HOST:PORT`, or `nil` if it sets none or couldn't
    /// be read.
    public var address: String?

    /// Whether others can read the file, which the command warns about.
    public var isReadableByOthers: Bool

    /// What keeps the file from being used, or `nil` if it can be used.
    public var problem: Problem?

  }

  /// What keeps a file from being used.
  public enum Problem: Hashable, Sendable {

    /// The file's type, owner or permissions make it unsafe to read.
    case refused(EnvironmentFile.Refusal)

    /// The file can't be opened, or isn't UTF-8 text.
    case unreadable

    /// A line of the file isn't `NAME=VALUE`; the value is its number, from 1.
    case malformed(line: Int)

    /// The file's name isn't a valid ``HubName``, so `--hub` can't name it.
    case unusableName

  }

  /// The directory of Hub files, or `nil` if neither `XDG_CONFIG_HOME` nor `HOME` is set.
  public var directory: String?

  /// The files, the default file first, then the named files in order of name.
  public var entries: [Entry]

  /// The name `INSTEON_HUB` gives when no file for it exists.
  public var missingVariableHub: String?

}

extension HubFiles {

  /// Lists the default file and the Hub files, reading each to find its address.
  ///
  /// - Returns: The listing. A file that can't be used is in it, with the reason.
  public func listing() -> HubListing {

    var entries: [HubListing.Entry] = []
    let variableName = variableHubName.flatMap { HubName.isValid($0) ? $0 : nil }

    if let path = EnvironmentFile.defaultPath(environment: environment), store.exists(atPath: path) {

      entries.append(entry(name: nil, path: path, isDefault: variableName == nil))

    }

    var missingVariableHub: String? = variableName

    for fileName in hubFileNames {

      let stem = String(fileName.dropLast(Self.fileExtension.count))

      guard let directory = hubsDirectory else {

        break

      }

      let path = directory + "/" + fileName

      guard HubName.isValid(stem) else {

        entries.append(HubListing.Entry(name: stem, path: path, isDefault: false, address: nil, isReadableByOthers: false, problem: .unusableName))

        continue

      }

      if stem == variableName {

        missingVariableHub = nil

      }

      entries.append(entry(name: stem, path: path, isDefault: stem == variableName))

    }

    return HubListing(directory: hubsDirectory, entries: entries, missingVariableHub: missingVariableHub)

  }

  /// The names of the files in the directory of Hub files that end in `.env`, sorted.
  private var hubFileNames: [String] {

    guard let directory = hubsDirectory, let entries = store.fileNames(inDirectory: directory) else {

      return []

    }

    return entries.filter { $0.hasSuffix(Self.fileExtension) && $0.count > Self.fileExtension.count }.sorted()

  }

  private func entry(name: String?, path: String, isDefault: Bool) -> HubListing.Entry {

    var entry = HubListing.Entry(name: name, path: path, isDefault: isDefault, address: nil, isReadableByOthers: false, problem: nil)
    var readableByOthers = false

    do {

      let contents = try store.read(at: path, warn: { (_: String) -> Void in readableByOthers = true })
      let variables = try DotEnv.parse(contents)

      entry.address = Self.address(in: variables)
      entry.isReadableByOthers = readableByOthers

    } catch let error as EnvironmentFileError {

      switch error {
      case let .refused(_, refusal):
        entry.problem = .refused(refusal)
      case .unreadable, .notFound:
        entry.problem = .unreadable
      }

    } catch let error as DotEnvError {

      switch error {
      case let .malformedLine(line):
        entry.problem = .malformed(line: line)
      }

    } catch {

      entry.problem = .unreadable

    }

    return entry

  }

  private static func address(in variables: [String: String]) -> String? {

    guard let host = variables[EnvironmentKey.hubHost], !host.isEmpty else {

      return nil

    }

    guard !host.contains(":"), let port = variables[EnvironmentKey.hubPort], !port.isEmpty else {

      return host

    }

    return host + ":" + port

  }

}
