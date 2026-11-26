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
