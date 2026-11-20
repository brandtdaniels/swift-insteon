import Testing
import InsteonCLISupport

/// A Hub file store over a dictionary, so the tests never touch the real home directory.
///
/// It decides what may be read with the same `EnvironmentFile.verdict` the real store uses, from
/// the mode and owner each file is given. A path that isn't absolute, which would read from the
/// current directory, is a test failure.
struct FakeHubFiles: HubFileStore {

  struct File {

    var contents: String

    var mode: Int = 0o100_600

    var ownerID: Int = 501

  }

  var files: [String: File] = [:]

  /// Directories that exist although no file in them is listed, such as an empty one.
  var emptyDirectories: Set<String> = []

  var currentUserID = 501

  /// Paths that are present but can't be opened.
  var unopenable: Set<String> = []

  init(_ contents: [String: String] = [:]) {

    files = contents.mapValues { File(contents: $0) }

  }

  func exists(atPath path: String) -> Bool {

    requireAbsolute(path)

    return files[path] != nil

  }

  func fileNames(inDirectory path: String) -> [String]? {

    requireAbsolute(path)

    let prefix = path + "/"
    let names = files.keys.filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }.map { String($0.dropFirst(prefix.count)) }

    return names.isEmpty && !emptyDirectories.contains(path) ? nil : names.sorted()

  }

  func read(at path: String, warn: (String) -> Void) throws(EnvironmentFileError) -> String {

    requireAbsolute(path)

    guard let file = files[path], !unopenable.contains(path) else {

      throw EnvironmentFileError.unreadable(path: path)

    }

    switch EnvironmentFile.verdict(mode: file.mode, ownerID: file.ownerID, currentUserID: currentUserID) {
    case .read:
      break
    case .readWithWarning:
      warn("others can read \(path)")
    case let .refuse(refusal):
      throw EnvironmentFileError.refused(path: path, refusal)
    }

    return file.contents

  }

  private func requireAbsolute(_ path: String) {

    #expect(path.hasPrefix("/"), "A Hub file is never read from the current directory: \(path)")

  }

}
