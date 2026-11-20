import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

/// The text of a refused catalog: invented devices and commands, since only the shape of each
/// difference matters.
struct CatalogRefusalTextTests {

  let published = DeviceCatalogVersion(major: 0, minor: 10, patch: 39)
  let bundled = DeviceCatalogVersion(major: 0, minor: 10, patch: 1)

  static func weakening(_ category: UInt8, _ subcategory: UInt8, _ kind: GuardWeakening.Kind, _ detail: String, firmware: UInt8? = nil) -> GuardWeakening {

    GuardWeakening(
      category: DeviceCategory(rawValue: category),
      subcategory: DeviceSubcategory(rawValue: subcategory),
      firmwareVersion: firmware.map { FirmwareVersion(rawValue: $0) },
      kind: kind,
      detail: detail
    )

  }

  /// One difference of each kind, two of them effect changes, given out of order.
  var small: [GuardWeakening] {

    [
      Self.weakening(0x03, 0x1F, .effect, "serial 0x64 payload 1 0x00 undescribed to link"),
      Self.weakening(0x01, 0x22, .effect, "extended cmd1 0x25 actuation to configuration"),
      Self.weakening(0x03, 0x01, .effect, "cmd1 0x30 link to undescribed"),
      Self.weakening(0x02, 0x05, .idempotent, "cmd1 0x11"),
      Self.weakening(0x01, 0x21, .effect, "extended cmd1 0x25 actuation to configuration"),
    ]

  }

  func refusal(_ weakenings: [GuardWeakening], current: DeviceCatalogVersion? = nil) -> CatalogRefusal {

    CatalogRefusal(published: published, bundled: bundled, current: current ?? bundled, weakenings: weakenings)

  }

  // MARK: - Grouping

  @Test func groupsDifferencesByKindInAFixedOrder() {

    let groups = CatalogRefusalText.groups(small)

    #expect(groups.map(\.kind) == [.effectChanged, .idempotencyChanged, .droppedEntry, .serialNowDescribed])
    #expect(groups.map(\.title) == ["Effect changes", "Idempotency changes", "Dropped entries", "Undescribed serial commands now described"])
    #expect(groups.map(\.differences.count) == [2, 1, 1, 1])
    #expect(groups.map(\.productCount) == [2, 1, 1, 1])

  }

  @Test func countsAProductOnceWhateverItsDifferencesOrFirmwareVersions() {

    let weakenings = [
      Self.weakening(0x01, 0x21, .effect, "cmd1 0x25 actuation to configuration"),
      Self.weakening(0x01, 0x21, .effect, "cmd1 0x26 actuation to configuration"),
      Self.weakening(0x01, 0x21, .effect, "cmd1 0x27 actuation to configuration", firmware: 0x45),
    ]

    let group = CatalogRefusalText.groups(weakenings)[0]

    #expect(group.differences.count == 3)
    #expect(group.productCount == 1)

  }

  @Test func putsAKindWithoutItsOwnGroupInOtherGuardChanges() {

    let groups = CatalogRefusalText.groups([Self.weakening(0x01, 0x7A, .flagBits, "Get Operating Flags 0x00 kept bits 0x40")])

    #expect(groups.map(\.kind) == [.other])
    #expect(groups.map(\.title) == ["Other guard changes"])

  }

  @Test func namesTheKindOfEachOtherGuardChange() {

    let other = Self.weakening(0x01, 0x7A, .unlocksProtectedCommand, "Set Operating Flags 0x0C")
    let lines = CatalogRefusalText.summary(refusal([other]))

    #expect(lines.contains("    0x01/0x7A  unlocksProtectedCommand Set Operating Flags 0x0C"))
    #expect(CatalogRefusalText.explanation(refusal([other])).last == "0x01/0x7A unlocksProtectedCommand Set Operating Flags 0x0C")

  }

  @Test func leavesOutAKindWithNoDifferences() {

    #expect(CatalogRefusalText.groups([]).isEmpty)

  }

  @Test func sortsEachGroupByDeviceThenDetailThenFirmware() {

    let weakenings = [
      Self.weakening(0x02, 0x01, .effect, "cmd1 0x30 link to actuation"),
      Self.weakening(0x01, 0x21, .effect, "cmd1 0x40 link to actuation", firmware: 0x50),
      Self.weakening(0x01, 0x21, .effect, "cmd1 0x40 link to actuation", firmware: 0x45),
      Self.weakening(0x01, 0x21, .effect, "cmd1 0x25 link to actuation"),
    ]

    let lines = CatalogRefusalText.groups(weakenings)[0].differences.map(\.description)

    #expect(
      lines == [
        "0x01/0x21 effect cmd1 0x25 link to actuation",
        "0x01/0x21 effect cmd1 0x40 link to actuation",
        "0x01/0x21 effect cmd1 0x40 link to actuation",
        "0x02/0x01 effect cmd1 0x30 link to actuation",
      ]
    )
    #expect(CatalogRefusalText.groups(weakenings)[0].differences.map { $0.firmwareVersion?.rawValue } == [nil, 0x45, 0x50, nil])

  }

  // MARK: - The summary

  @Test func summarizesARefusalWithExamplesAndTheHintLast() {

    #expect(
      CatalogRefusalText.summary(refusal(small)) == [
        "The published Insteon device catalog, 0.10.39, relaxes safeguards that the bundled copy, 0.10.1,",
        "keeps, so it isn't used.",
        "",
        "5 differences in 4 kinds, across 5 products:",
        "",
        "Effect changes: 2 differences across 2 products",
        "    0x01/0x21  extended cmd1 0x25 actuation to configuration",
        "    0x01/0x22  extended cmd1 0x25 actuation to configuration",
        "Idempotency changes: 1 difference across 1 product",
        "    0x02/0x05  cmd1 0x11",
        "Dropped entries: 1 difference across 1 product",
        "    0x03/0x01  cmd1 0x30 link to undescribed",
        "Undescribed serial commands now described: 1 difference across 1 product",
        "    0x03/0x1F  serial 0x64 payload 1 0x00 undescribed to link",
        "",
        "The bundled copy, 0.10.1, stays until a new version of this tool ships a refreshed bundle.",
        "Run 'insteon catalog update --explain' to see every difference, one per line.",
      ]
    )

  }

  @Test func showsTheFirstThreeExamplesOfAKindAndCountsTheRest() {

    let weakenings = (1...5).map { (number: UInt8) -> GuardWeakening in Self.weakening(0x01, number, .effect, "cmd1 0x25 actuation to configuration") }
    let lines = CatalogRefusalText.summary(refusal(weakenings))

    #expect(
      Array(lines[5...9]) == [
        "Effect changes: 5 differences across 5 products",
        "    0x01/0x01  cmd1 0x25 actuation to configuration",
        "    0x01/0x02  cmd1 0x25 actuation to configuration",
        "    0x01/0x03  cmd1 0x25 actuation to configuration",
        "    and 2 more",
      ]
    )

  }

  @Test func namesTheCurrentCopyWhenItIsNotTheBundledOne() {

    let cached = DeviceCatalogVersion(major: 0, minor: 10, patch: 5)
    let lines = CatalogRefusalText.summary(refusal(small, current: cached))

    #expect(
      Array(lines[(lines.count - 3)...]) == [
        "The current copy, 0.10.5, stays, and the bundled copy, 0.10.1, stays until a new version of this",
        "tool ships a refreshed bundle.",
      ] + ["Run 'insteon catalog update --explain' to see every difference, one per line."]
    )
    #expect(lines[lines.count - 4] == "")

  }

  @Test func wrapsLongLinesAtOneHundredCharactersWithAHangingIndent() {

    let detail = "extended cmd1 0x2E cmd2 0x00 D1 0x01 D2 0x02 D3 0x03 D4 0x04 D5 0x05 D6 0x06 D7 0x07 D8 0x08 actuation to configuration"
    let lines = CatalogRefusalText.summary(refusal([Self.weakening(0x01, 0x21, .effect, detail)]))

    #expect(lines.allSatisfy { $0.count <= 100 })
    #expect(lines[6] == "    0x01/0x21  extended cmd1 0x2E cmd2 0x00 D1 0x01 D2 0x02 D3 0x03 D4 0x04 D5 0x05 D6 0x06 D7 0x07")
    #expect(lines[7] == "      D8 0x08 actuation to configuration")

  }

  @Test func keepsEveryLineOfALargeRefusalWithinOneHundredCharacters() {

    let weakenings = (0...255).flatMap { (subcategory: Int) -> [GuardWeakening] in

      [
        Self.weakening(0x01, UInt8(subcategory), .effect, "extended cmd1 0x25 cmd2 0x00 D1 0x01 D2 0x02 D3 0x03 D4 0x04 D5 0x05 actuation to configuration"),
        Self.weakening(0x01, UInt8(subcategory), .idempotent, "cmd1 0x11"),
      ]

    }
    let lines = CatalogRefusalText.summary(refusal(weakenings))

    #expect(lines.allSatisfy { $0.count <= 100 })
    #expect(lines.count < 30)
    #expect(lines.contains("Effect changes: 256 differences across 256 products"))

  }

  // MARK: - The complete list

  @Test func explainsEveryDifferenceOnItsOwnLineGroupedAndSorted() {

    let weakenings = small + [Self.weakening(0x01, 0x21, .effect, "extended cmd1 0x26 link to actuation", firmware: 0x45)]

    #expect(
      CatalogRefusalText.explanation(refusal(weakenings)) == [
        "Effect changes: 3 differences across 2 products",
        "0x01/0x21 extended cmd1 0x25 actuation to configuration",
        "0x01/0x21 (firmware 0x45) extended cmd1 0x26 link to actuation",
        "0x01/0x22 extended cmd1 0x25 actuation to configuration",
        "",
        "Idempotency changes: 1 difference across 1 product",
        "0x02/0x05 cmd1 0x11",
        "",
        "Dropped entries: 1 difference across 1 product",
        "0x03/0x01 cmd1 0x30 link to undescribed",
        "",
        "Undescribed serial commands now described: 1 difference across 1 product",
        "0x03/0x1F serial 0x64 payload 1 0x00 undescribed to link",
      ]
    )

  }

  @Test func explainsTheSameListWhateverTheOrderItIsGiven() {

    #expect(CatalogRefusalText.explanation(refusal(small)) == CatalogRefusalText.explanation(refusal(small.reversed())))

  }

  @Test func explainsAsStructuredJSON() throws {

    let json = try CatalogRefusalText.explanationJSON(refusal(small))
    let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let groups = try #require(object["groups"] as? [[String: Any]])

    #expect(object["status"] as? String == "refused")
    #expect(object["published"] as? String == "0.10.39")
    #expect(object["bundled"] as? String == "0.10.1")
    #expect(object["current"] as? String == "0.10.1")
    #expect(groups.map { $0["kind"] as? String } == ["effectChanged", "idempotencyChanged", "droppedEntry", "serialNowDescribed"])
    #expect(groups.map { $0["count"] as? Int } == [2, 1, 1, 1])
    #expect(groups.map { $0["products"] as? Int } == [2, 1, 1, 1])

    let first = try #require((groups[0]["differences"] as? [[String: Any]])?.first)

    #expect(first["category"] as? String == "0x01")
    #expect(first["subcategory"] as? String == "0x21")
    #expect(first["kind"] as? String == "effect")
    #expect(first["detail"] as? String == "extended cmd1 0x25 actuation to configuration")
    #expect(first["firmwareVersion"] == nil)

  }

}
