import Foundation

/// A uniquely named directory under the system's temporary directory, removed when it goes
/// out of use. Tests and the equivalence harness build trees in one.
public final class ScratchDirectory {
  /// The directory.
  public let url: URL

  public init(prefix: String = "repo-checks") throws {
    url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  /// The URL of a path under the directory, given with `/` between components.
  public func url(for relativePath: String) -> URL {
    relativePath.split(separator: "/").reduce(url) { $0.appendingPathComponent(String($1)) }
  }

  /// Writes the data at the path under the directory, creating the directories above it.
  public func write(_ data: Data, to relativePath: String) throws {
    let file = url(for: relativePath)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: file)
  }

  /// Writes the text, as UTF-8, at the path under the directory.
  public func write(_ text: String, to relativePath: String) throws {
    try write(Data(text.utf8), to: relativePath)
  }

  /// Creates the directory at the path under the directory.
  public func makeDirectory(_ relativePath: String) throws {
    try FileManager.default.createDirectory(at: url(for: relativePath), withIntermediateDirectories: true)
  }
}
