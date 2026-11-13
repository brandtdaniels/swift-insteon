import Foundation
import Testing
import InsteonCLISupport

/// Where `insteon observe` puts the file, and the summary it prints beside it.
struct ObservationDeliveryTests {

  /// Files in memory.
  final class Files: ObservationFiles {

    var written: [String: Data] = [:]

    var existing: Set<String> = []

    func createFile(_ data: Data, at path: String) throws -> Bool {

      guard !existing.contains(path), written[path] == nil else {

        return false

      }

      written[path] = data

      return true

    }

  }

  let json = Data("{}\n".utf8)

  @Test func printsTheJSONWhenNoPathIsGiven() throws {

    let files = Files()

    let delivery = try ObservationDelivery.deliver(json, to: nil, files: files)

    #expect(delivery == .standardOutput("{}"))
    #expect(files.written.isEmpty)

  }

  @Test func writesTheJSONToThePathGiven() throws {

    let files = Files()

    let delivery = try ObservationDelivery.deliver(json, to: "observation.json", files: files)

    #expect(delivery == .file("observation.json"))
    #expect(files.written["observation.json"] == json)

  }

  @Test func refusesToOverwriteAFileThatIsThere() {

    let files = Files()
    files.existing = ["observation.json"]

    #expect(throws: CommandFailure(description: "observation.json already exists, so nothing was written. Give --output another path, or remove the file first.")) {

      try ObservationDelivery.deliver(json, to: "observation.json", files: files)

    }

    #expect(files.written.isEmpty)

  }

  // MARK: - The summary

  private func observation(model: String?) throws -> Observation {

    let findings = ObservationFindings(
      engine: "i2CS",
      category: "0x7E",
      subcategory: "0x7F",
      firmware: "0x41",
      model: model,
      productKey: nil,
      operatingFlags: nil,
      checks: [
        ObservationCheckResult(name: "ID Request", outcome: .answered, detail: "The device reported its identity."),
        ObservationCheckResult(name: "Get Operating Flags", outcome: .silent, detail: "No answer.")
      ]
    )

    return try Observation(findings, tool: ObservationTool(name: "insteon", version: "1"), catalogVersion: "0.9.1", note: nil, observedOn: Date(timeIntervalSince1970: 0))

  }

  @Test func summarizesTheChecksWithTheirOutcomes() throws {

    let lines = try ObservationText.summary(observation(model: "Example Invented Product"))

    #expect(lines == [
      "Observed Example Invented Product, engine i2CS:",
      "",
      "answered  ID Request           The device reported its identity.",
      "silent    Get Operating Flags  No answer. It may need to be awake."
    ])

  }

  @Test func namesADeviceTheCatalogDoesntIdentifyByItsCategoryAndSubcategory() throws {

    #expect(try ObservationText.summary(observation(model: nil)).first == "Observed a device of category 0x7E and subcategory 0x7F, engine i2CS:")

  }

  @Test func tellsWhereTheFileWentAndWhatItHolds() {

    #expect(ObservationText.closing(.file("observation.json")) == [
      "Wrote observation.json. It holds no address of a device, the modem or a Hub, and no account data; "
        + "look it over, then attach it to an issue or a pull request."
    ])
    #expect(ObservationText.closing(.standardOutput("{}")).isEmpty)

  }

}
