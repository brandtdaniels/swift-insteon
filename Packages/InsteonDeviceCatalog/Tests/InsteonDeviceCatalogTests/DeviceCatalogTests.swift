import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonProtocol

struct DeviceCatalogTests {

  /// A catalog in the published format, with `profiles` as its devices.
  static func json(_ profiles: String, schemaVersion: Int = 1) -> Data {

    Data(#"{ "schemaVersion": \#(schemaVersion), "devices": [\#(profiles)] }"#.utf8)

  }

  static let leakSensor = #"""
    {
      "model": "2852",
      "name": "Leak Sensor",
      "identities": [
        { "category": "0x10", "subcategory": "0x08", "region": "US" },
        { "category": "0x10", "subcategory": "0x0D", "region": "Europe" }
      ],
      "radio": "rf",
      "role": "controller",
      "batteryPowered": true,
      "groups": [
        { "number": "0x01", "name": "Dry", "role": "controller" },
        { "number": "0x02", "name": "Wet", "role": "controller", "linkable": "software" },
        { "number": "0x04", "name": "Heartbeat", "role": "controller" }
      ],
      "capabilities": [
        {
          "kind": "groupEvents",
          "events": [
            { "group": "0x01", "command1": "0x11", "event": "dry" },
            { "group": "0x02", "command1": "0x11", "event": "wet" }
          ]
        },
        { "kind": "heartbeat", "group": "0x04", "intervalMinutes": 1428 },
        { "kind": "somethingNewer", "detail": 1 }
      ],
      "notes": ["Its heartbeat sends on when dry and off when wet."],
      "sources": ["HouseLinc device catalog"]
    }
    """#

  /// Two versions of one product, told apart by firmware.
  static let dimmers = #"""
    {
      "model": "1000",
      "name": "Early Dimmer",
      "identities": [{ "category": "0x01", "subcategory": "0x20", "firmware": { "from": "0x00", "through": "0x3F" } }],
      "capabilities": [{ "kind": "dimmable" }],
      "sources": ["A"]
    },
    {
      "model": "1001",
      "name": "Later Dimmer",
      "identities": [{ "category": "0x01", "subcategory": "0x20", "firmware": { "from": "0x40", "through": "0xFF" } }],
      "capabilities": [{ "kind": "dimmable" }, { "kind": "thermostat", "modeValues": "tempLinc", "humidity": true }],
      "sources": ["B"]
    }
    """#

  @Test func readsAProfile() throws {

    let catalog = try DeviceCatalog(json: Self.json(Self.leakSensor))

    #expect(catalog.profiles == [
      DeviceProfile(
        model: "2852",
        name: "Leak Sensor",
        identities: [
          DeviceIdentity(category: 0x10, subcategory: 0x08, region: "US"),
          DeviceIdentity(category: 0x10, subcategory: 0x0D, region: "Europe"),
        ],
        radio: .rf,
        role: .controller,
        isBatteryPowered: true,
        groups: [
          .init(number: 0x01, name: "Dry", role: .controller),
          .init(number: 0x02, name: "Wet", role: .controller, linking: .software),
          .init(number: 0x04, name: "Heartbeat", role: .controller),
        ],
        // The capability of a kind this package doesn't read is skipped.
        capabilities: [
          .groupEvents([
            .init(group: 0x01, command1: 0x11, event: "dry"),
            .init(group: 0x02, command1: 0x11, event: "wet"),
          ]),
          .heartbeat(group: 0x04, interval: .seconds(1428 * 60)),
        ],
        notes: ["Its heartbeat sends on when dry and off when wet."],
        sources: ["HouseLinc device catalog"]
      ),
    ])

  }

  @Test func readsANameAliasesAndDescription() throws {

    let profile = #"""
      {
        "model": "2477D",
        "name": "Dimmer Switch",
        "aliases": ["SwitchLinc Dimmer"],
        "description": "An in-wall dimmer switch.",
        "identities": [{ "category": "0x01", "subcategory": "0x20" }],
        "capabilities": [{ "kind": "dimmable" }],
        "sources": ["A"]
      }
      """#
    let read = try #require(try DeviceCatalog(json: Self.json(profile)).profiles.first)

    #expect(read.name == "Dimmer Switch")
    #expect(read.aliases == ["SwitchLinc Dimmer"])
    #expect(read.summary == "An in-wall dimmer switch.")

  }

  @Test func searchesModelsNamesAliasesAndIdentities() throws {

    let catalog = try DeviceCatalog.bundled()

    #expect(catalog.profiles(matching: "0x01/0x20").map(\.model) == ["2477D"])
    #expect(catalog.profiles(matching: "SWITCHLINC dimmer").contains { $0.model == "2477D" })
    #expect(catalog.profiles(matching: "2852").map(\.model) == ["2852"])
    #expect(catalog.profiles(matching: "").count == catalog.profiles.count)
    #expect(catalog.profiles(matching: "no such product").isEmpty)

  }

  @Test func findsAProfileByIdentityOrModel() throws {

    let catalog = try DeviceCatalog(json: Self.json(Self.leakSensor))

    #expect(catalog.profile(category: 0x10, subcategory: 0x0D, firmwareVersion: 0x41)?.model == "2852")
    #expect(catalog.profile(category: 0x10, subcategory: 0x08, firmwareVersion: nil)?.model == "2852")
    #expect(catalog.profile(category: 0x10, subcategory: 0x09, firmwareVersion: nil) == nil)
    #expect(catalog.profile(model: "2852")?.name == "Leak Sensor")
    #expect(catalog.profile(model: "2853") == nil)

  }

  @Test func tellsFirmwareVersionsApart() throws {

    let catalog = try DeviceCatalog(json: Self.json(Self.dimmers))

    #expect(catalog.profile(category: 0x01, subcategory: 0x20, firmwareVersion: 0x3F)?.model == "1000")
    #expect(catalog.profile(category: 0x01, subcategory: 0x20, firmwareVersion: 0x40)?.model == "1001")
    // Without a firmware version, neither range can be chosen.
    #expect(catalog.profile(category: 0x01, subcategory: 0x20, firmwareVersion: nil) == nil)
    #expect(catalog.profile(model: "1001")?.capabilities.last == .thermostat(modeValues: .tempLinc, measuresHumidity: true))

  }

  @Test func prefersAnIdentityForParticularFirmware() throws {

    let profiles = #"""
      {
        "model": "1000",
        "name": "Any Version",
        "identities": [{ "category": "0x01", "subcategory": "0x20" }],
        "capabilities": [],
        "sources": ["A"]
      },
      {
        "model": "1001",
        "name": "Later Versions",
        "identities": [{ "category": "0x01", "subcategory": "0x20", "firmware": { "from": "0x40", "through": "0xFF" } }],
        "capabilities": [],
        "sources": ["B"]
      }
      """#
    let catalog = try DeviceCatalog(json: Self.json(profiles))

    #expect(catalog.profile(category: 0x01, subcategory: 0x20, firmwareVersion: 0x45)?.model == "1001")
    #expect(catalog.profile(category: 0x01, subcategory: 0x20, firmwareVersion: 0x3F)?.model == "1000")
    // 0xFF means the device gave no version.
    #expect(catalog.profile(category: 0x01, subcategory: 0x20, firmwareVersion: 0xFF)?.model == "1000")

  }

  // A later version of the catalog can add values this package doesn't read.
  @Test func passesOverValuesItDoesntRead() throws {

    let profile = #"""
      {
        "model": "1",
        "name": "A",
        "identities": [{ "category": "0x05", "subcategory": "0x01" }],
        "radio": "infrared",
        "role": "observer",
        "groups": [
          { "number": "0x01", "name": "Kept", "role": "controller", "linkable": "remotely" },
          { "number": "0x02", "name": "Skipped", "role": "observer" }
        ],
        "capabilities": [{ "kind": "thermostat", "modeValues": "venstar" }, { "kind": "dimmable" }],
        "sources": ["A"]
      }
      """#
    let read = try #require(try DeviceCatalog(json: Self.json(profile)).profiles.first)

    #expect(read.radio == nil)
    #expect(read.role == nil)
    #expect(read.groups == [.init(number: 0x01, name: "Kept", role: .controller, linking: .software)])
    #expect(read.capabilities == [.dimmable])

  }

  @Test(arguments: [0, 525_601, Int.max])
  func refusesAHeartbeatIntervalOutOfRange(_ minutes: Int) {

    let profile = #"{ "model": "1", "name": "A", "identities": [{ "category": "0x10", "subcategory": "0x01" }], "capabilities": [{ "kind": "heartbeat", "group": "0x04", "intervalMinutes": \#(minutes) }], "sources": ["A"] }"#

    #expect(throws: DecodingError.self) {

      try DeviceCatalog(json: Self.json(profile))

    }

  }

  @Test func saysWhatAGroupCommandMeans() throws {

    let profile = try #require(try DeviceCatalog(json: Self.json(Self.leakSensor)).profiles.first)

    #expect(profile.event(group: 0x02, command1: 0x11) == "wet")
    #expect(profile.event(group: 0x02, command1: 0x13) == nil)
    #expect(profile.heartbeatInterval == .seconds(1428 * 60))

  }

  @Test func refusesAnotherFormatVersion() {

    #expect(throws: DeviceCatalogError.unsupportedSchemaVersion(2)) {

      try DeviceCatalog(json: Self.json(Self.leakSensor, schemaVersion: 2))

    }

  }

  @Test(arguments: ["0x1", "0x1g", "0x1a", "10", "0x100"])
  func refusesABadlyWrittenByte(_ byte: String) {

    let profile = #"{ "model": "1", "name": "A", "identities": [{ "category": "\#(byte)", "subcategory": "0x01" }], "capabilities": [], "sources": ["A"] }"#

    #expect(throws: DecodingError.self) {

      try DeviceCatalog(json: Self.json(profile))

    }

  }

  @Test func refusesAFirmwareRangeThatEndsBeforeItStarts() {

    let profile = #"{ "model": "1", "name": "A", "identities": [{ "category": "0x01", "subcategory": "0x01", "firmware": { "from": "0x40", "through": "0x3F" } }], "capabilities": [], "sources": ["A"] }"#

    #expect(throws: DecodingError.self) {

      try DeviceCatalog(json: Self.json(profile))

    }

  }

  @Test func readsI2CSForSomeIdentitiesAndFirmware() throws {

    let profile = #"""
      {
        "model": "1",
        "name": "Dimmer Switch",
        "identities": [
          { "category": "0x01", "subcategory": "0x19" },
          { "category": "0x01", "subcategory": "0x30" },
          { "category": "0x01", "subcategory": "0x31" }
        ],
        "capabilities": [
          { "kind": "dimmable" },
          {
            "kind": "i2cs",
            "identities": [
              { "category": "0x01", "subcategory": "0x19", "firmware": { "only": ["0x41", "0xD1"] } },
              { "category": "0x01", "subcategory": "0x30", "firmware": { "except": ["0x38"] } }
            ]
          }
        ],
        "sources": ["A"]
      }
      """#
    let read = try #require(try DeviceCatalog(json: Self.json(profile)).profiles.first)

    #expect(read.capabilities.last == .i2cs(.identities([
      ScopedIdentity(category: 0x01, subcategory: 0x19, firmware: .only([0x41, 0xD1])),
      ScopedIdentity(category: 0x01, subcategory: 0x30, firmware: .except([0x38])),
    ])))

    #expect(read.runsI2CS(category: 0x01, subcategory: 0x19, firmwareVersion: 0xD1))
    #expect(!read.runsI2CS(category: 0x01, subcategory: 0x19, firmwareVersion: 0x40))
    #expect(read.runsI2CS(category: 0x01, subcategory: 0x30, firmwareVersion: 0x40))
    #expect(!read.runsI2CS(category: 0x01, subcategory: 0x30, firmwareVersion: 0x38))
    #expect(!read.runsI2CS(category: 0x01, subcategory: 0x31, firmwareVersion: 0x41))

    // Without a firmware version, or with 0xFF, a selection can't include the device.
    #expect(!read.runsI2CS(category: 0x01, subcategory: 0x19, firmwareVersion: nil))
    #expect(!read.runsI2CS(category: 0x01, subcategory: 0x30, firmwareVersion: 0xFF))

    #expect(read.capabilities(category: 0x01, subcategory: 0x31, firmwareVersion: 0x41) == [.dimmable])

  }

  @Test func readsI2CSForEveryVersion() throws {

    let profile = #"{ "model": "1", "name": "A", "identities": [{ "category": "0x01", "subcategory": "0x01" }], "capabilities": [{ "kind": "i2cs" }], "sources": ["A"] }"#
    let read = try #require(try DeviceCatalog(json: Self.json(profile)).profiles.first)

    #expect(read.capabilities == [.i2cs(.everyVersion)])
    #expect(read.runsI2CS(category: 0x01, subcategory: 0x01, firmwareVersion: nil))

  }

  @Test func refusesAFirmwareSelectionWithBothOrNeither() {

    for selection in [#"{ "only": ["0x41"], "except": ["0x40"] }"#, "{}"] {

      let profile = #"{ "model": "1", "name": "A", "identities": [{ "category": "0x01", "subcategory": "0x01" }], "capabilities": [{ "kind": "i2cs", "identities": [{ "category": "0x01", "subcategory": "0x01", "firmware": \#(selection) }] }], "sources": ["A"] }"#

      #expect(throws: DecodingError.self) {

        try DeviceCatalog(json: Self.json(profile))

      }

    }

  }

  @Test func loadsTheBundledCopy() throws {

    let catalog = try DeviceCatalog.bundled()

    #expect(catalog.profile(category: 0x01, subcategory: 0x20, firmwareVersion: 0x41)?.model == "2477D")
    #expect(catalog.profile(category: 0x10, subcategory: 0x08, firmwareVersion: nil)?.event(group: 0x02, command1: 0x11) == "wet")

    // HouseLinc lists 0x41 under the 2476D's checksum class for subcategory 0x19, and 0x38
    // under its earlier class.
    let dimmer = try #require(catalog.profile(model: "2476D"))
    #expect(dimmer.runsI2CS(category: 0x01, subcategory: 0x19, firmwareVersion: 0x41))
    #expect(!dimmer.runsI2CS(category: 0x01, subcategory: 0x19, firmwareVersion: 0x38))

    // The published catalog never has two profiles claim one identity.
    for profile in catalog.profiles {

      for identity in profile.identities where identity.firmware == nil {

        #expect(catalog.profile(category: identity.category, subcategory: identity.subcategory, firmwareVersion: nil) == profile)

      }

    }

  }

}
