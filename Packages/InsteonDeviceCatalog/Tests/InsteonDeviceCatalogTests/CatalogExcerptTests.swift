import Foundation
import Testing
import InsteonDeviceCatalog
import InsteonProtocol

/// Excerpts of the catalog's own data in the format with linking from a Hub, group state
/// patterns, outputs and arm modes, copied as they're published: the EZFlora's zone 2, the
/// 0-10V Ballast Dimmer's light, the Siren's first alarm and arming groups, and the Wireless
/// Thermostat's linking from a Hub.
struct CatalogExcerptTests {

  static let commandSet = #"""
    {
      "id": "excerpts",
      "name": "Excerpts",
      "description": "Group types copied from the catalog's ezFlora, inLineLinc0To10V and siren command sets.",
      "groupTypes": [
        {
          "name": "zone2",
          "label": "Zone 2",
          "kind": "relay",
          "state": {
            "command": "readValveStatus",
            "onWhen": {
              "mask": "0x87",
              "value": "0x81",
              "verification": {
                "status": "inferred",
                "note": "Read from the valve status byte as the EZFlora Insteon and X10 Messages/Commands give it: bits 0 to 2 the active valve and bit 7 whether a valve is on. That a zone is on only while it's the active valve and bit 7 is set is read from the byte naming one active valve; no document says so."
              }
            }
          },
          "actions": [
            {
              "name": "on",
              "label": "On",
              "command": "valveOn",
              "value": "0x01"
            },
            {
              "name": "off",
              "label": "Off",
              "command": "valveOff",
              "value": "0x01"
            }
          ]
        },
        {
          "name": "light",
          "label": "Light",
          "kind": "dimmer",
          "state": {
            "command": "readStatus"
          },
          "actions": [
            {
              "name": "on",
              "label": "On",
              "command": "lightOn"
            },
            {
              "name": "off",
              "label": "Off",
              "command": "lightOff"
            }
          ],
          "outputs": {
            "activeWhen": {
              "flag": "relayMode",
              "set": true
            },
            "bits": [
              {
                "mask": "0x01",
                "name": "relay1",
                "label": "Relay 1"
              },
              {
                "mask": "0x02",
                "name": "relay2",
                "label": "Relay 2"
              }
            ]
          },
          "verification": {
            "status": "documented",
            "note": "In relay mode, cmd2 of Light On is a mask of the relays to close, bit 0 relay 1 and bit 1 relay 2, rather than a level."
          }
        },
        {
          "name": "soundAway",
          "label": "Sound when armed away",
          "kind": "alarm",
          "armModes": [
            "away"
          ],
          "verification": {
            "status": "conflicting",
            "note": "The Siren Module Developer Notes' introduction swaps home and away for groups 1 to 4; their group table, used here, doesn't."
          }
        },
        {
          "name": "armAway",
          "label": "Arm away",
          "kind": "arming",
          "armModes": [
            "away"
          ],
          "verification": {
            "status": "conflicting",
            "note": "The Siren Module Developer Notes' introduction swaps home and away for groups 1 to 4; their group table, used here, doesn't."
          }
        }
      ],
      "sources": [
        "A"
      ]
    }
    """#

  static let thermostat = #"""
    {
      "model": "2441ZTH",
      "name": "Wireless Thermostat",
      "identities": [
        {
          "category": "0x05",
          "subcategory": "0x0A"
        }
      ],
      "batteryPowered": true,
      "capabilities": [],
      "lifecycle": {
        "fromHub": {
          "legs": [
            {
              "modem": "responder",
              "modemGroup": "0x01",
              "deviceGroup": "0x01"
            },
            {
              "modem": "responder",
              "modemGroup": "0x02",
              "deviceGroup": "0x02"
            },
            {
              "modem": "responder",
              "modemGroup": "0x03",
              "deviceGroup": "0x03"
            },
            {
              "modem": "responder",
              "modemGroup": "0x04",
              "deviceGroup": "0x04"
            }
          ],
          "deviceFirst": true,
          "remoteEnterLinkingMode": {
            "works": "unknown",
            "verification": {
              "status": "inferred",
              "note": "The device sleeps to save its battery and hears messages only while awake, and no document or observation says it answers Enter Linking Mode (cmd1 0x09); its linking steps put it in linking mode with its own controls."
            }
          },
          "keepAwake": {
            "when": "beforeLinking",
            "send": {
              "command1": "0x20",
              "command2": "0x06",
              "extended": true,
              "integrity": "checksum"
            },
            "release": {
              "command1": "0x20",
              "command2": "0x07",
              "extended": true,
              "integrity": "checksum"
            },
            "seconds": 240,
            "verification": {
              "status": "inferred",
              "note": "The Wireless Thermostat Developer Notes give Set Operating Flags (cmd1 0x20) as an extended message with a checksum, cmd2 0x06 to stay awake for 4 minutes and cmd2 0x07 to sleep in 3 seconds. Sending it once a person has woken the thermostat and before linking is assembled from this profile's waking and linking steps; no document describes adding this product to a Hub. Sending it before linking needs the thermostat's Insteon ID beforehand, such as from its label."
            }
          },
          "verification": {
            "status": "inferred",
            "note": "Read from the From a Hub alternative to this profile's linking, whose steps are assembled from its own linking steps and standard Insteon commands; no document describes adding this product to a Hub."
          }
        }
      },
      "sources": [
        "A"
      ]
    }
    """#

  static func catalog() throws -> DeviceCatalog {

    try DeviceCatalog(json: Data(#"{ "devices": [\#(thermostat)], "commandSets": [\#(commandSet)] }"#.utf8))

  }

  @Test func readsAnEZFloraZonesStatePattern() throws {

    let zone = try #require(try Self.catalog().commandSet(id: "excerpts")?.groupType(named: "zone2"))
    let onWhen = try #require(zone.state?.onWhen)

    #expect(onWhen.mask == 0x87)
    #expect(onWhen.value == 0x81)
    #expect(onWhen.verification.status == .inferred)
    // Zone 2 active with a valve on, zone 2 active with the valves off, and zone 1 on.
    #expect(onWhen.isOn(command2: 0x81))
    #expect(!onWhen.isOn(command2: 0x01))
    #expect(!onWhen.isOn(command2: 0x80))

  }

  @Test func readsABallastDimmersOutputs() throws {

    let light = try #require(try Self.catalog().commandSet(id: "excerpts")?.groupType(named: "light"))
    let outputs = try #require(light.outputs)

    #expect(light.kind == .dimmer)
    #expect(outputs.activeWhen == DeviceProfile.Group.Condition(flag: "relayMode", isSet: true))
    #expect(outputs.bits.map(\.mask) == [0x01, 0x02])
    #expect(outputs.bits.map(\.label) == ["Relay 1", "Relay 2"])

  }

  @Test func readsASirensArmModes() throws {

    let commands = try #require(try Self.catalog().commandSet(id: "excerpts"))

    #expect(commands.groupType(named: "soundAway")?.kind == .alarm)
    #expect(commands.groupType(named: "soundAway")?.armModes == [.away])
    #expect(commands.groupType(named: "armAway")?.kind == .arming)
    #expect(commands.groupType(named: "armAway")?.armModes == [.away])

  }

  @Test func readsAWirelessThermostatsLinkingFromAHub() throws {

    let fromHub = try #require(try Self.catalog().profile(model: "2441ZTH")?.lifecycle?.fromHub)
    let keepAwake = try #require(fromHub.keepAwake)

    #expect(fromHub.isDeviceFirst)
    #expect(fromHub.legs.map(\.modemRole) == [.responder, .responder, .responder, .responder])
    #expect(fromHub.legs.map(\.deviceGroup) == [1, 2, 3, 4])
    #expect(fromHub.legs.map(\.modemGroup) == [1, 2, 3, 4])
    #expect(fromHub.legs.allSatisfy { $0.verification == fromHub.verification })
    #expect(fromHub.remoteEnterLinkingMode?.works == .unknown)
    #expect(keepAwake.timing == .beforeLinking)
    #expect(keepAwake.send == .bytes(DeviceLifecycle.HubLinking.RawMessage(command: Command(command1: 0x20, command2: 0x06), isExtended: true, integrity: .checksum)))
    #expect(keepAwake.release == .bytes(DeviceLifecycle.HubLinking.RawMessage(command: Command(command1: 0x20, command2: 0x07), isExtended: true, integrity: .checksum)))
    #expect(keepAwake.duration == .seconds(240))
    #expect(keepAwake.verification.status == .inferred)

  }

}
