/// The per-user file the `insteon` command reads environment variables from, such as the Hub's
/// credentials, and the checks it makes before reading it.
///
/// The file is `$XDG_CONFIG_HOME/insteon/env`, or `~/.config/insteon/env` when
/// `XDG_CONFIG_HOME` isn't set, unless `--env-file PATH` names another. It's never read from the
/// current directory, where a cloned project's file could point the command, and the password,
/// at someone else's Hub. Its lines are read by ``DotEnv/parse(_:)``.
///
/// The command reads the file only if it's a regular file, owned by the person running the
/// command, that no one else can write to, and it warns if others can read it.
///
/// ```swift
/// let path = EnvironmentFile.path(explicit: nil, environment: ["HOME": "/home/example"])
/// // "/home/example/.config/insteon/env"
///
/// EnvironmentFile.verdict(mode: 0o100600, ownerID: 501, currentUserID: 501)
/// // .read
/// ```
public enum EnvironmentFile {

  /// The file's path inside the configuration directory: `insteon/env`.
  public static let relativePath = "insteon/env"

  /// What the command does with the file, after checking its owner and permissions.
  public enum Verdict: Hashable, Sendable {

    /// Read the file.
    case read

    /// Read the file, but warn that other people can read it too.
    case readWithWarning

    /// Don't read the file, for the reason given.
    case refuse(Refusal)

  }

  /// Why the command won't read the file.
  public enum Refusal: Hashable, Sendable {

    /// The path isn't a regular file, such as a directory.
    case notRegularFile

    /// Someone other than the person running the command owns the file.
    case ownedByAnotherUser

    /// The file's group or everyone can write to it.
    case writableByOthers

  }

  /// The file to read: the one `--env-file` names, or else the per-user default.
  ///
  /// - Parameters:
  ///   - explicit: The path given with `--env-file`, if any.
  ///   - environment: The process's environment, for `XDG_CONFIG_HOME` and `HOME`.
  /// - Returns: The path, or `nil` if there's no `--env-file` and neither `XDG_CONFIG_HOME` nor
  ///   `HOME` is set.
  public static func path(explicit: String?, environment: [String: String]) -> String? {

    if let explicit {

      return explicit

    }

    return defaultPath(environment: environment)

  }

  /// The per-user default: `$XDG_CONFIG_HOME/insteon/env`, or `$HOME/.config/insteon/env`.
  ///
  /// `XDG_CONFIG_HOME` is used only when it's an absolute path, as the XDG Base Directory
  /// Specification asks.
  ///
  /// - Parameter environment: The process's environment.
  /// - Returns: The path, or `nil` if neither `XDG_CONFIG_HOME` nor `HOME` is set.
  public static func defaultPath(environment: [String: String]) -> String? {

    if let configHome = environment["XDG_CONFIG_HOME"], configHome.hasPrefix("/") {

      return joined(configHome, relativePath)

    }

    guard let home = environment["HOME"], home.hasPrefix("/") else {

      return nil

    }

    return joined(joined(home, ".config"), relativePath)

  }

  /// Decides whether to read the file from its metadata, as `stat` gives it.
  ///
  /// - Parameters:
  ///   - mode: The file's type and permission bits, `st_mode`.
  ///   - ownerID: The user ID of the file's owner, `st_uid`.
  ///   - currentUserID: The user ID of the person running the command, from `getuid()`.
  /// - Returns: Whether to read the file, warn about it, or refuse it.
  public static func verdict(mode: Int, ownerID: Int, currentUserID: Int) -> Verdict {

    let fileTypeMask = 0o170_000
    let regularFile = 0o100_000
    let writableByGroupOrOthers = 0o022
    let readableByGroupOrOthers = 0o044

    guard mode & fileTypeMask == regularFile else {

      return .refuse(.notRegularFile)

    }

    guard ownerID == currentUserID else {

      return .refuse(.ownedByAnotherUser)

    }

    guard mode & writableByGroupOrOthers == 0 else {

      return .refuse(.writableByOthers)

    }

    return mode & readableByGroupOrOthers == 0 ? .read : .readWithWarning

  }

  private static func joined(_ directory: String, _ name: String) -> String {

    directory.hasSuffix("/") ? directory + name : directory + "/" + name

  }

}

/// An environment file the `insteon` command won't or can't read.
///
/// The error names the file, never its contents, which may hold a password.
public enum EnvironmentFileError: Error, Hashable, Sendable {

  /// The file `--env-file` names doesn't exist.
  case notFound(path: String)

  /// The file exists but couldn't be opened, or isn't UTF-8 text.
  case unreadable(path: String)

  /// The file's type, owner or permissions make it unsafe to read.
  case refused(path: String, EnvironmentFile.Refusal)

}

extension EnvironmentFileError: CustomStringConvertible {

  /// The error as a one-line message for the person who typed the command.
  public var description: String {

    switch self {
    case let .notFound(path):
      "The environment file \(path) doesn't exist."
    case let .unreadable(path):
      "The environment file \(path) couldn't be read as UTF-8 text."
    case let .refused(path, .notRegularFile):
      "The environment file \(path) isn't a regular file, so it wasn't read."
    case let .refused(path, .ownedByAnotherUser):
      "The environment file \(path) belongs to another user, so it wasn't read. Use a file you own, readable only by you (chmod 600)."
    case let .refused(path, .writableByOthers):
      "Others can change the environment file \(path), so it wasn't read. Make it readable only by you: chmod 600 \(path)"
    }

  }

}
