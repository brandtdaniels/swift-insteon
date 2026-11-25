import Foundation
import Testing

@testable import RepoCheckSupport

@Suite("SourceFiles")
struct SourceFilesTests {
  @Test("orders component by component, so a directory's files come before a sibling that sorts later as text")
  func ordersByComponent() throws {
    let directory = try ScratchDirectory()
    try directory.write("", to: "a/b.swift")
    try directory.write("", to: "a.md")
    try directory.write("", to: "a-b.md")

    let paths = try SourceFiles.entries(under: directory.url).map(\.relativePath)

    #expect(paths == ["a", "a/b.swift", "a-b.md", "a.md"])
  }

  @Test("orders names by code point, an uppercase name before a lowercase one")
  func ordersByCodePoint() throws {
    let directory = try ScratchDirectory()
    for name in ["beta.md", "Zeta.md", "alpha.md", "\u{E9}.md"] {
      try directory.write("", to: name)
    }

    let paths = try SourceFiles.entries(under: directory.url).map(\.relativePath)

    #expect(paths == ["Zeta.md", "alpha.md", "beta.md", "\u{E9}.md"])
  }

  @Test("leaves out, without descending, the pruned names")
  func prunes() throws {
    let directory = try ScratchDirectory()
    try directory.write("", to: ".build/x/y.swift")
    try directory.write("", to: ".git/config")
    try directory.write("", to: "Sources/.build/z.swift")
    try directory.write("", to: "Sources/kept.swift")

    let paths = try SourceFiles.entries(under: directory.url).map(\.relativePath)

    #expect(paths == ["Sources", "Sources/kept.swift"])
  }

  @Test("tells files from directories and doesn't follow a symbolic link")
  func marksDirectories() throws {
    let directory = try ScratchDirectory()
    try directory.write("", to: "d/f.txt")
    try FileManager.default.createSymbolicLink(
      at: directory.url(for: "link"),
      withDestinationURL: directory.url(for: "d")
    )

    let entries = try SourceFiles.entries(under: directory.url)

    #expect(entries.map(\.relativePath) == ["d", "d/f.txt", "link"])
    #expect(entries.map(\.isDirectory) == [true, false, false])
  }

  @Test("a path is its entry's components under the root")
  func buildsURL() throws {
    let directory = try ScratchDirectory()
    let entry = SourceEntry(components: ["a", "b.txt"], isDirectory: false)

    #expect(entry.url(under: directory.url).path == directory.url(for: "a/b.txt").path)
  }
}
