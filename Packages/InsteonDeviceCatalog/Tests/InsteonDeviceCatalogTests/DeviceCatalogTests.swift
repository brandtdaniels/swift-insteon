import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonProtocol

struct DeviceCatalogTests {

  /// A catalog in the published format, with `profiles` as its devices.
  static func json(_ profiles: String) -> Data {

    Data(#"{ "devices": [\#(profiles)] }"#.utf8)

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
      "capabilities": [{ "kind": "dimmable" }, { "kind": "thermostat", "humidity": true }],
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

  @Test func readsHowSureTheCatalogIsOfAProfile() throws {

    let profile = #"""
      {
        "model": "2476SS",
        "name": "On/Off Switch with Sense",
        "identities": [
          { "category": "0x02", "subcategory": "0x15", "verification": { "status": "conflicting", "note": "Two lists." } },
          { "category": "0x02", "subcategory": "0x16" }
        ],
        "engines": [{ "engine": "i2cs", "category": "0x02", "subcategory": "0x15",
          "verification": { "status": "observed", "note": "A device reported it.", "firmware": ["0x41"] } }],
        "commandSets": [{ "commandSet": "relay", "category": "0x02", "subcategory": "0x15",
          "verification": { "status": "inferred", "note": "A similar product." } }],
        "groups": [{ "number": "0x01", "name": "Load", "role": "both",
          "verification": { "status": "inferred", "note": "Its manual." } }],
        "capabilities": [],
        "sources": ["A"],
        "verification": { "status": "inferred", "note": "No document names it." }
      }
      """#
    let read = try #require(try DeviceCatalog(json: Self.json(profile)).profiles.first)

    #expect(read.verification == Verification(status: .inferred, note: "No document names it."))
    #expect(read.identities.map(\.verification.status) == [.conflicting, .documented])
    #expect(read.engines.first?.verification.firmware == [0x41])
    #expect(read.commandSets.first?.verification.status == .inferred)
    #expect(read.groups.first?.verification.status == .inferred)

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
    #expect(catalog.profile(model: "1001")?.capabilities.last == .thermostat(measuresHumidity: true))

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
        "capabilities": [{ "kind": "somethingNewer" }, { "kind": "dimmable" }],
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

  // The version is in the manifest, not the catalog, so a key the catalog doesn't have, or
  // one from a later version, is passed over.
  @Test func passesOverKeysItDoesntRead() throws {

    let json = Data(#"{ "schemaVersion": 1, "somethingNewer": {}, "devices": [\#(Self.leakSensor)] }"#.utf8)

    let read = try DeviceCatalog(json: json)
    let expected = try DeviceCatalog(json: Self.json(Self.leakSensor))

    #expect(read == expected)

  }

  // A new MAJOR.MINOR is a new format: check that the package reads it before changing these.
  @Test func readsTheBundledVersion() throws {

    let version = try DeviceCatalog.bundledVersion()

    #expect(version.major == 0)
    #expect(version.minor == 6)

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

  @Test func readsTheEngineForEachIdentityAndFirmware() throws {

    let profile = #"""
      {
        "model": "1",
        "name": "I/O Module",
        "identities": [
          { "category": "0x07", "subcategory": "0x00" },
          { "category": "0x07", "subcategory": "0x01" },
          { "category": "0x07", "subcategory": "0x02" }
        ],
        "engines": [
          { "engine": "i1", "category": "0x07", "subcategory": "0x00", "firmware": { "only": ["0x31"] } },
          { "engine": "i2cs", "category": "0x07", "subcategory": "0x00", "firmware": { "only": ["0x41", "0xA1"] } },
          { "engine": "i2", "category": "0x07", "subcategory": "0x01", "firmware": { "except": ["0x41"] } },
          { "engine": "i3", "category": "0x07", "subcategory": "0x02" }
        ],
        "capabilities": [],
        "sources": ["A"]
      }
      """#
    let read = try #require(try DeviceCatalog(json: Self.json(profile)).profiles.first)

    // The entry for an engine this package doesn't read is skipped.
    #expect(read.engines == [
      DeviceEngine(engine: .i1, category: 0x07, subcategory: 0x00, firmware: .only([0x31])),
      DeviceEngine(engine: .i2cs, category: 0x07, subcategory: 0x00, firmware: .only([0x41, 0xA1])),
      DeviceEngine(engine: .i2, category: 0x07, subcategory: 0x01, firmware: .except([0x41])),
    ])

    #expect(read.engine(category: 0x07, subcategory: 0x00, firmwareVersion: 0x31) == .i1)
    #expect(read.engine(category: 0x07, subcategory: 0x00, firmwareVersion: 0xA1) == .i2cs)
    #expect(read.engine(category: 0x07, subcategory: 0x00, firmwareVersion: 0x40) == nil)
    #expect(read.engine(category: 0x07, subcategory: 0x01, firmwareVersion: 0x40) == .i2)
    #expect(read.engine(category: 0x07, subcategory: 0x01, firmwareVersion: 0x41) == nil)
    #expect(read.engine(category: 0x07, subcategory: 0x02, firmwareVersion: 0x41) == nil)

    // Without a firmware version, or with 0xFF, a selection can't include the device.
    #expect(read.engine(category: 0x07, subcategory: 0x00, firmwareVersion: nil) == nil)
    #expect(read.engine(category: 0x07, subcategory: 0x01, firmwareVersion: 0xFF) == nil)

  }

  @Test func readsAnEngineForEveryVersion() throws {

    let profile = #"{ "model": "1", "name": "A", "identities": [{ "category": "0x01", "subcategory": "0x01" }], "engines": [{ "engine": "i2cs", "category": "0x01", "subcategory": "0x01" }], "capabilities": [], "sources": ["A"] }"#
    let read = try #require(try DeviceCatalog(json: Self.json(profile)).profiles.first)

    #expect(read.engine(category: 0x01, subcategory: 0x01, firmwareVersion: nil) == .i2cs)
    #expect(read.engine(category: 0x01, subcategory: 0x02, firmwareVersion: nil) == nil)

  }

  @Test func refusesAFirmwareSelectionWithBothOrNeither() {

    for selection in [#"{ "only": ["0x41"], "except": ["0x40"] }"#, "{}"] {

      let profile = #"{ "model": "1", "name": "A", "identities": [{ "category": "0x01", "subcategory": "0x01" }], "engines": [{ "engine": "i2cs", "category": "0x01", "subcategory": "0x01", "firmware": \#(selection) }], "capabilities": [], "sources": ["A"] }"#

      #expect(throws: DecodingError.self) {

        try DeviceCatalog(json: Self.json(profile))

      }

    }

  }

  @Test func loadsTheBundledCopy() throws {

    let catalog = try DeviceCatalog.bundled()

    #expect(catalog.profile(category: 0x01, subcategory: 0x20, firmwareVersion: 0x41)?.model == "2477D")
    #expect(catalog.profile(category: 0x10, subcategory: 0x08, firmwareVersion: nil)?.event(group: 0x02, command1: 0x11) == "wet")

    // The motion sensors' events, which once had types of their own.
    let motionSensorII = try #require(catalog.profile(model: "2844"))
    #expect(motionSensorII.event(group: 0x01, command1: 0x11) == "motion")
    #expect(motionSensorII.event(group: 0x05, command1: 0x11) == "motionStopped")
    #expect(motionSensorII.event(group: 0x06, command1: 0x11) == "light")
    #expect(catalog.profile(model: "2842")?.event(group: 0x01, command1: 0x13) == "motionStopped")
    #expect(catalog.profile(model: "2842")?.heartbeatGroup == 0x04)
    #expect(catalog.profile(model: "2982-222")?.event(group: 0x07, command1: 0x11) == "malfunction")

    // HouseLinc lists 0x41 under the 2476D's checksum class for subcategory 0x19, and 0x38
    // under its earlier class.
    let dimmer = try #require(catalog.profile(model: "2476D"))
    #expect(dimmer.engine(category: 0x01, subcategory: 0x19, firmwareVersion: 0x41) == .i2cs)
    #expect(dimmer.engine(category: 0x01, subcategory: 0x19, firmwareVersion: 0x38) == nil)

    // The published catalog never has two profiles claim one identity.
    for profile in catalog.profiles {

      for identity in profile.identities where identity.firmware == nil {

        #expect(catalog.profile(category: identity.category, subcategory: identity.subcategory, firmwareVersion: nil) == profile)

      }

    }

  }

}
