import Foundation
import Testing
import InsteonLinking
import InsteonProtocol
@testable import InsteonCore

/// The scenes of a network as a backup holds it: the cached ALL-Link databases, with no read from hardware.
struct SceneListingBackupTests {

  let modem = InsteonAddress(0x11, 0x22, 0x33)
  let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  let keypad = InsteonAddress(0x4D, 0x5E, 0x6F)

  private func backup(modem records: [BackupRecord]?, devices: [BackupDevice]) -> NetworkBackup {

    let held: BackupModem = records.map { BackupModem(address: modem, allLinkDatabase: $0) } ?? BackupModem(address: modem, unreadable: BackupUnreadable(reason: .notCached))

    return NetworkBackup(createdAt: Date(timeIntervalSince1970: 1_800_000_000), source: .service, modem: held, devices: devices)

  }

  private func record(_ role: BackupRecordRole, group: UInt8, _ address: InsteonAddress, data: [UInt8] = [0xFF, 0x1F, 0x01], state: BackupRecordState = .inUse) -> BackupRecord {

    BackupRecord(state: state, role: role, group: group, address: address, data: data)

  }

  private func device(_ address: InsteonAddress, _ records: [BackupRecord]) -> BackupDevice {

    BackupDevice(address: address, allLinkDatabase: BackupDatabase(delta: 0x01, records: records))

  }

  @Test func listsAGroupTheModemControlsAsAWritableSceneWithTheResponderDataItHolds() {

    let held = backup(
      modem: [record(.controller, group: 3, lamp)],
      devices: [device(lamp, [record(.responder, group: 3, modem, data: [0x80, 0x1C, 0x00])])]
    )
    let listing = SceneListing(held)

    #expect(listing.scenes.count == 1)
    #expect(listing.scenes.first?.number == 3)
    #expect(listing.scenes.first?.controller == .modem)
    #expect(listing.scenes.first?.isWritable == true)
    #expect(listing.scenes.first?.members == [SceneListing.Member(address: lamp, data: [0x80, 0x1C, 0x00])])
    #expect(listing.isWhole)

  }

  @Test func listsAGroupADeviceControlsAsReadOnly() {

    let held = backup(
      modem: [record(.responder, group: 2, keypad)],
      devices: [device(keypad, [record(.controller, group: 2, modem)])]
    )
    let listing = SceneListing(held)

    #expect(listing.scenes.first?.controller == .device(keypad))
    #expect(listing.scenes.first?.isWritable == false)

  }

  @Test func ignoresRecordsThatAreNotInUse() {

    let held = backup(
      modem: [record(.controller, group: 3, lamp, state: .free), record(.controller, group: 0, InsteonAddress(0, 0, 0), state: .end)],
      devices: [device(lamp, [record(.responder, group: 3, modem, state: .free)])]
    )

    #expect(SceneListing(held).scenes.isEmpty)
    #expect(SceneListing(held).isWhole)

  }

  @Test func reportsADeviceWithNoCachedDatabaseSoTheListingIsNotWhole() {

    let held = backup(
      modem: [record(.controller, group: 3, lamp)],
      devices: [BackupDevice(address: lamp, unreadable: BackupUnreadable(reason: .notCached))]
    )
    let listing = SceneListing(held)

    #expect(listing.unreadable == [lamp])
    #expect(!listing.isWhole)

  }

  @Test func reportsAModemWithNoCachedDatabaseAsUnreadableAndListsNoScenes() {

    let held = backup(modem: nil, devices: [device(lamp, [record(.responder, group: 3, modem)])])
    let listing = SceneListing(held)

    #expect(listing.scenes.isEmpty)
    #expect(listing.isModemUnread)
    #expect(!listing.isWhole)

  }

  @Test func keepsARecordWhoseOtherHalfIsMissingAsAHalfLink() {

    let held = backup(modem: [record(.controller, group: 3, lamp)], devices: [device(lamp, [])])
    let listing = SceneListing(held)

    #expect(listing.scenes.first?.halfLinks.count == 1)
    #expect(listing.scenes.first?.members.isEmpty == true)
    #expect(!listing.isWhole)

  }

  @Test func listsADeviceTheRecordsNameButTheBackupLacksAsUnlisted() {

    let held = backup(modem: [record(.controller, group: 3, lamp)], devices: [])

    #expect(SceneListing(held).unlisted == [lamp])
    #expect(!SceneListing(held).isWhole)

  }

  @Test func aBackupWithNoModemListsNothingAndIsNotWhole() {

    let held = NetworkBackup(createdAt: Date(timeIntervalSince1970: 1_800_000_000), source: .service, modem: nil, devices: [])

    #expect(SceneListing(held).scenes.isEmpty)
    #expect(SceneListing(held).isModemUnread)
    #expect(!SceneListing(held).isWhole)

  }

  @Test func aListingOfAReadingIsNotMarkedModemUnread() {

    #expect(!SceneListing(scenes: []).isModemUnread)

  }

}
