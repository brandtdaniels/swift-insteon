import Foundation

/// Runs a check with `--update` and reports the file it wrote as part of its output, so the
/// bytes of the written allow-list or list are compared too. The file is put back afterwards.
public struct UpdatingRunner: CheckRunning {
  private let base: ProcessCheckRunner
  private let file: String

  /// - Parameters:
  ///   - base: The runner of the check with `--update` among its arguments.
  ///   - file: The file the check writes, relative to the tree.
  public init(base: ProcessCheckRunner, file: String) {
    self.base = base
    self.file = file
  }

  public func run(in tree: URL) throws -> CheckOutput {
    let url = file.split(separator: "/").reduce(tree) { $0.appendingPathComponent(String($1)) }
    let before = try? Data(contentsOf: url)
    defer {
      if let before {
        try? before.write(to: url)
      } else {
        try? FileManager.default.removeItem(at: url)
      }
    }
    var output = try base.run(in: tree)
    let written = (try? Data(contentsOf: url)) ?? Data("(no file)".utf8)
    output.standardOutput.append(Data("\n--- \(file) ---\n".utf8))
    output.standardOutput.append(written)
    return output
  }
}
