import Foundation
import RepoCheckSupport
import Testing

@testable import RepoChecks

@Suite("check-app-thin")
struct AppThinCheckTests {
  private func run(_ files: [String: String]) throws -> (status: CheckStatus, output: String) {
    let directory = try ScratchDirectory()
    for (path, text) in files {
      try directory.makeDirectory((path as NSString).deletingLastPathComponent)
      try directory.write(text, to: path)
    }
    let console = RecordingConsole()
    let status = try AppThinCheck().run(in: directory.url, console: console)
    return (status, console.output)
  }

  @Test("passes on the libraries an app may use and the frameworks that host it")
  func allowedImports() throws {
    let result = try run([
      "Apps/InsteonApp/Sources/InsteonAppUI/Screen.swift": """
        import Foundation
        import InsteonCore
        import InsteonService
        import Observation
        import SwiftUI
        @testable import InsteonDemo
        public import InsteonClient

        """
    ])

    #expect(result.status == .passed)
  }

  @Test("fails on a lower-level Insteon module, naming the file and line")
  func lowerLevelModules() throws {
    let result = try run([
      "Apps/InsteonApp/Sources/InsteonAppUI/Screen.swift": "import SwiftUI\nimport InsteonProtocol\nimport InsteonModem\n"
    ])

    #expect(result.status == .failed)
    #expect(result.output.contains("Apps/InsteonApp/Sources/InsteonAppUI/Screen.swift:2: imports InsteonProtocol"))
    #expect(result.output.contains("Screen.swift:3: imports InsteonModem"))
  }

  @Test("fails on a framework that has no place in a thin interface")
  func unlistedFramework() throws {
    let result = try run(["Apps/InsteonApp/Sources/InsteonAppUI/Net.swift": "import Network\n"])

    #expect(result.status == .failed)
    #expect(result.output.contains("imports Network"))
  }

  @Test("does not read an import in a comment or a string, or the tests")
  func ignoresWhatIsNotAnImport() throws {
    let result = try run([
      "Apps/InsteonApp/Sources/InsteonAppUI/Screen.swift": "// import InsteonProtocol\nlet text = \"import InsteonModem\"\n",
      "Apps/InsteonApp/Tests/InsteonAppUITests/Screen.swift": "import InsteonProtocol\n"
    ])

    #expect(result.status == .passed)
  }

  @Test("reads the keyword forms, a submodule path and a trailing semicolon", arguments: [
    "import struct InsteonProtocol.Address", "import class InsteonModem.Modem", "import enum InsteonLinking.Kind",
    "import func InsteonHubClient.open", "import typealias InsteonProtocol.Alias", "import protocol InsteonLinking.LinkingModem",
    "import var InsteonProtocol.constant", "import InsteonProtocol.Messages", "import InsteonProtocol;", "import  InsteonProtocol  ;",
    "@preconcurrency import InsteonProtocol", "@_exported public import InsteonProtocol"
  ])
  func importForms(line: String) throws {
    let result = try run(["Apps/InsteonApp/Sources/InsteonAppUI/Screen.swift": line + "\n"])

    #expect(result.status == .failed, "\(line)")
    #expect(result.output.contains("imports Insteon"), "\(line)")
  }

  @Test("reads the keyword forms of an allowed module as allowed")
  func allowedKeywordForms() throws {
    let result = try run(["Apps/InsteonApp/Sources/InsteonAppUI/Screen.swift": "import struct InsteonCore.InsteonAddress;\nimport SwiftUI.Foo\n"])

    #expect(result.status == .passed, "\(result.output)")
  }

  @Test("reads a file directly under Sources and one in a deeper directory")
  func everySwiftFileUnderSources() throws {
    let result = try run([
      "Apps/InsteonApp/Sources/Top.swift": "import InsteonProtocol\n",
      "Apps/InsteonApp/Sources/A/B/C/Deep.swift": "import InsteonModem\n"
    ])

    #expect(result.output.contains("Apps/InsteonApp/Sources/Top.swift:1: imports InsteonProtocol"))
    #expect(result.output.contains("Apps/InsteonApp/Sources/A/B/C/Deep.swift:1: imports InsteonModem"))
  }

  @Test("passes with no apps")
  func noApps() throws {
    #expect(try run([:]).status == .passed)
  }

  @Test("passes on this repository")
  func repositoryPasses() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let console = RecordingConsole()

    #expect(try AppThinCheck().run(in: root, console: console) == .passed, "\(console.output)")
  }
}
