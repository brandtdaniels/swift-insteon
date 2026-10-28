import Foundation
import Testing
import InsteonDeviceDatabase
import InsteonProtocol

struct DeviceDatabaseTests {

  /// A database in the published format, with `profiles` as its devices.
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

    let database = try DeviceDatabase(json: Self.json(Self.leakSensor))

    #expect(database.profiles == [
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

  @Test func findsAProfileByIdentityOrModel() throws {

    let database = try DeviceDatabase(json: Self.json(Self.leakSensor))

    #expect(database.profile(category: 0x10, subcategory: 0x0D, firmwareVersion: 0x41)?.model == "2852")
    #expect(database.profile(category: 0x10, subcategory: 0x08, firmwareVersion: nil)?.model == "2852")
    #expect(database.profile(category: 0x10, subcategory: 0x09, firmwareVersion: nil) == nil)
    #expect(database.profile(model: "2852")?.name == "Leak Sensor")
    #expect(database.profile(model: "2853") == nil)

  }

  @Test func tellsFirmwareVersionsApart() throws {

    let database = try DeviceDatabase(json: Self.json(Self.dimmers))

    #expect(database.profile(category: 0x01, subcategory: 0x20, firmwareVersion: 0x3F)?.model == "1000")
    #expect(database.profile(category: 0x01, subcategory: 0x20, firmwareVersion: 0x40)?.model == "1001")
    // Without a firmware version, neither range can be chosen.
    #expect(database.profile(category: 0x01, subcategory: 0x20, firmwareVersion: nil) == nil)
    #expect(database.profile(model: "1001")?.capabilities.last == .thermostat(modeValues: .tempLinc, measuresHumidity: true))

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
    let database = try DeviceDatabase(json: Self.json(profiles))

    #expect(database.profile(category: 0x01, subcategory: 0x20, firmwareVersion: 0x45)?.model == "1001")
    #expect(database.profile(category: 0x01, subcategory: 0x20, firmwareVersion: 0x3F)?.model == "1000")
    // 0xFF means the device gave no version.
    #expect(database.profile(category: 0x01, subcategory: 0x20, firmwareVersion: 0xFF)?.model == "1000")

  }

  // A later version of the database can add values this package doesn't read.
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
    let read = try #require(try DeviceDatabase(json: Self.json(profile)).profiles.first)

    #expect(read.radio == nil)
    #expect(read.role == nil)
    #expect(read.groups == [.init(number: 0x01, name: "Kept", role: .controller, linking: .software)])
    #expect(read.capabilities == [.dimmable])

  }

  @Test(arguments: [0, 525_601, Int.max])
  func refusesAHeartbeatIntervalOutOfRange(_ minutes: Int) {

    let profile = #"{ "model": "1", "name": "A", "identities": [{ "category": "0x10", "subcategory": "0x01" }], "capabilities": [{ "kind": "heartbeat", "group": "0x04", "intervalMinutes": \#(minutes) }], "sources": ["A"] }"#

    #expect(throws: DecodingError.self) {

      try DeviceDatabase(json: Self.json(profile))

    }

  }

  @Test func saysWhatAGroupCommandMeans() throws {

    let profile = try #require(try DeviceDatabase(json: Self.json(Self.leakSensor)).profiles.first)

    #expect(profile.event(group: 0x02, command1: 0x11) == "wet")
    #expect(profile.event(group: 0x02, command1: 0x13) == nil)
    #expect(profile.heartbeatInterval == .seconds(1428 * 60))

  }

  @Test func refusesAnotherFormatVersion() {

    #expect(throws: DeviceDatabaseError.unsupportedSchemaVersion(2)) {

      try DeviceDatabase(json: Self.json(Self.leakSensor, schemaVersion: 2))

    }

  }

  @Test(arguments: ["0x1", "0x1g", "0x1a", "10", "0x100"])
  func refusesABadlyWrittenByte(_ byte: String) {

    let profile = #"{ "model": "1", "name": "A", "identities": [{ "category": "\#(byte)", "subcategory": "0x01" }], "capabilities": [], "sources": ["A"] }"#

    #expect(throws: DecodingError.self) {

      try DeviceDatabase(json: Self.json(profile))

    }

  }

  @Test func refusesAFirmwareRangeThatEndsBeforeItStarts() {

    let profile = #"{ "model": "1", "name": "A", "identities": [{ "category": "0x01", "subcategory": "0x01", "firmware": { "from": "0x40", "through": "0x3F" } }], "capabilities": [], "sources": ["A"] }"#

    #expect(throws: DecodingError.self) {

      try DeviceDatabase(json: Self.json(profile))

    }

  }

  @Test func loadsTheBundledCopy() throws {

    let database = try DeviceDatabase.bundled()

    #expect(database.profile(category: 0x01, subcategory: 0x20, firmwareVersion: 0x41)?.model == "2477D")
    #expect(database.profile(category: 0x10, subcategory: 0x08, firmwareVersion: nil)?.event(group: 0x02, command1: 0x11) == "wet")

    // The published database never has two profiles claim one identity.
    for profile in database.profiles {

      for identity in profile.identities where identity.firmware == nil {

        #expect(database.profile(category: identity.category, subcategory: identity.subcategory, firmwareVersion: nil) == profile)

      }

    }

  }

}
