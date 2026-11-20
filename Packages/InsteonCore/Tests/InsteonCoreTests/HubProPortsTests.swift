import Foundation
import Testing
@testable import InsteonCore
import InsteonDeviceCatalog

@Suite(.timeLimit(.minutes(1)))
struct HubProPortsTests {

  private func catalog(_ capabilities: [[String]]) throws -> ProductCatalog {

    let devices = capabilities.enumerated().map { index, kinds in

      """
      { "model": "98\(index)1", "name": "Example Bridge \(index)", "identities": [{ "category": "0x03", "subcategory": "0x7\(index)" }],
        "commandSets": [], "groups": [], "capabilities": [\(kinds.joined(separator: ","))], "sources": ["A"] }
      """

    }

    return try ProductCatalog(DeviceCatalog(json: Data(#"{ "devices": [\#(devices.joined(separator: ","))], "commandSets": [] }"#.utf8)))

  }

  @Test func givesEachPortTheCatalogNamesForAHubProsInterfaceOnce() throws {

    let catalog = try catalog([
      [#"{ "kind": "hubPro", "port": 8081 }"#, #"{ "kind": "hub", "port": 25105 }"#],
      [#"{ "kind": "hubPro", "port": 80 }"#],
      [#"{ "kind": "hubPro", "port": 8081 }"#],
    ])

    #expect(catalog.hubProPorts == [80, 8081])

  }

  @Test func givesNoPortWhenNoProductHasAHubProInterface() throws {

    #expect(try catalog([[#"{ "kind": "hub", "port": 25105 }"#]]).hubProPorts.isEmpty)

  }

}
