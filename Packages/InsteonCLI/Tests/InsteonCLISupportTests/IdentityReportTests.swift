import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonProtocol

/// What `insteon device ADDRESS id` asks a device, and what it prints.
@Suite(.timeLimit(.minutes(1)))
struct IdentityReportTests {

  let device = InsteonAddress(0x1A, 0x2B, 0x3C)

  /// What a report asked for.
  final class Asked {

    var productData: Int = 0

    var names: [String] = []

  }

  private func read(
    acceptsModem: Bool,
    identity: IdentityReport.Answer?,
    productData: DeviceProductData = DeviceProductData(category: 0x7E, subcategory: 0x7F, productKey: ProductKey(0x00, 0x00, 0x1A)),
    asked: Asked = Asked()
  ) async throws -> IdentityReport {

    try await IdentityReport.read(
      device,
      identify: { identity ?? IdentityReport.Answer(engine: .i2cs, acceptsModem: acceptsModem) },
      productData: { () -> DeviceProductData? in

        asked.productData += 1

        return productData

      },
      catalogInfo: { nil },
      productName: { (category: DeviceCategory, subcategory: DeviceSubcategory, firmware: FirmwareVersion?) -> String? in

        asked.names.append("\(category) \(subcategory) \(firmware.map { "\($0)" } ?? "none")")

        return "Example Invented Product"

      }
    )

  }

  private var identity: IdentityReport.Answer {

    IdentityReport.Answer(engine: .i2cs, acceptsModem: true, category: 0x7E, subcategory: 0x7D, firmwareVersion: 0x41)

  }

  // MARK: - What's asked

  @Test func asksForProductDataOnlyWhenTheDeviceTakesTheModemsCommands() async throws {

    let accepts = Asked()
    let rejects = Asked()

    let accepted = try await read(acceptsModem: true, identity: identity, asked: accepts)
    let rejected = try await read(acceptsModem: false, identity: nil, asked: rejects)

    #expect(accepts.productData == 1)
    #expect(accepted.productData != nil)
    #expect(rejects.productData == 0)
    #expect(rejected.productData == nil)

  }

  @Test func takesTheCategoryFromTheIdentityElseFromProductData() async throws {

    let asked = Asked()
    let identified = try await read(acceptsModem: true, identity: identity, asked: asked)
    let unidentified = try await read(acceptsModem: true, identity: nil, asked: asked)

    #expect(identified.category == 0x7E)
    #expect(identified.subcategory == 0x7D)
    #expect(unidentified.category == 0x7E)
    #expect(unidentified.subcategory == 0x7F)
    #expect(asked.names == ["0x7E 0x7D 0x41", "0x7E 0x7F none"])

  }

  @Test func namesNoProductWithoutACategory() async throws {

    let asked = Asked()
    let report = try await read(acceptsModem: false, identity: nil, asked: asked)

    #expect(report.category == nil)
    #expect(report.product == nil)
    #expect(asked.names.isEmpty)

  }

  // MARK: - What's printed

  @Test func printsTheIdentityAndTheProductWithACatalog() async throws {

    let report = try await read(acceptsModem: true, identity: identity)

    #expect(IdentityText.rows(report, namesProducts: true) == [
      ["Device:", "1A.2B.3C"],
      ["Engine:", Names.engine(.i2cs)],
      ["Category:", Names.category(0x7E)],
      ["Subcategory:", "0x7D"],
      ["Firmware:", "0x41"],
      ["Product key:", "0x00001A"],
      ["Product:", "Example Invented Product"]
    ])

  }

  @Test func saysWhatWasntReportedAndLeavesOutTheProductWithoutAnIdentityOrCatalog() async throws {

    let unidentified = try await read(acceptsModem: false, identity: nil)
    let identified = try await read(acceptsModem: true, identity: identity)

    #expect(IdentityText.rows(unidentified, namesProducts: true) == [
      ["Device:", "1A.2B.3C"],
      ["Engine:", Names.engine(.i2cs)],
      ["Category:", "not reported"],
      ["Subcategory:", "not reported"],
      ["Firmware:", "not reported"],
      ["Product key:", IdentityText.productKey(reported: nil, answered: false, catalog: nil)]
    ])
    #expect(IdentityText.rows(identified, namesProducts: false).count == 6)

  }

  @Test func saysAProductIsntInTheCatalog() async throws {

    var report = try await read(acceptsModem: true, identity: identity)
    report.product = nil

    #expect(IdentityText.rows(report, namesProducts: true).last == ["Product:", "not in the Insteon device catalog"])

  }

  @Test func printsTheIdentityAsJSON() async throws {

    let report = try await read(acceptsModem: true, identity: identity)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    let json = String(decoding: try encoder.encode(IdentityText.JSON(report)), as: UTF8.self)

    #expect(json == """
      {"acceptsModem":true,"address":"1A.2B.3C","category":"0x7E",\
      "engine":"\(Names.engine(.i2cs))","firmwareVersion":"0x41","product":"Example Invented Product",\
      "productKey":"0x00001A","subcategory":"0x7D"}
      """)

  }

}
