import InsteonLinking
import InsteonProtocol
import Testing
@testable import InsteonCore

/// Scenes as a client sees them, listed from a reading of the ALL-Link databases.
@Suite(.timeLimit(.minutes(1)))
struct SceneListingTests {

  static let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)
  static let plug = InsteonAddress(0x4D, 0x5E, 0x6F)
  static let remote = InsteonAddress(0x0A, 0x0B, 0x0C)

  static func group(_ number: UInt8) -> AllLinkGroupNumber { AllLinkGroupNumber(rawValue: number) }

  static func record(_ flags: AllLinkRecordFlags, group: UInt8, _ address: InsteonAddress) -> AllLinkRecord {

    AllLinkRecord(flags: flags, group: Self.group(group), address: address, data1: 0xFF, data2: 0x1F, data3: 0x01)

  }

  @Test func listsAGroupTheModemControlsAsAWritableSceneWithItsMembers() {

    let reading = AllLinkGroupReading(
      groups: [AllLinkGroup(controller: .modem, number: Self.group(5), responders: [
        AllLinkGroup.Responder(.device(Self.lamp), data1: 0xFF, data2: 0x1F, data3: 0x01),
        AllLinkGroup.Responder(.device(Self.plug), data1: 0x80, data2: 0x20, data3: 0x02)
      ])],
      halfLinks: [], unreadable: [], unlisted: []
    )
    let scene = SceneListing(reading).scenes[0]

    #expect(scene.number == 5)
    #expect(scene.controller == .modem)
    #expect(scene.isWritable)
    #expect(scene.members.map(\.address) == [Self.lamp, Self.plug])
    #expect(scene.members[0].data == [0xFF, 0x1F, 0x01])
    #expect(scene.members[1].data == [0x80, 0x20, 0x02])

  }

  @Test func listsAGroupADeviceControlsAsReadOnly() {

    let reading = AllLinkGroupReading(
      groups: [AllLinkGroup(controller: .device(Self.remote), number: Self.group(3), responders: [AllLinkGroup.Responder(.device(Self.lamp))])],
      halfLinks: [], unreadable: [], unlisted: []
    )
    let scene = SceneListing(reading).scenes[0]

    #expect(scene.controller == .device(Self.remote))
    #expect(!scene.isWritable)

  }

  @Test func listsGroupZeroOfTheModemAsReadOnlyBecauseTheAPINeverCreatesIt() {

    let reading = AllLinkGroupReading(groups: [AllLinkGroup(controller: .modem, number: Self.group(0), responders: [AllLinkGroup.Responder(.device(Self.lamp))])], halfLinks: [], unreadable: [], unlisted: [])

    #expect(!SceneListing(reading).scenes[0].isWritable)

  }

  @Test func listsGroups1Through254OfTheModemAsWritableAndNoOther() {

    for (number, writable) in [(UInt8(0), false), (1, true), (254, true), (255, false)] {

      let reading = AllLinkGroupReading(groups: [AllLinkGroup(controller: .modem, number: Self.group(number), responders: [AllLinkGroup.Responder(.device(Self.lamp))])], halfLinks: [], unreadable: [], unlisted: [])

      #expect(SceneListing(reading).scenes[0].isWritable == writable)

    }

  }

  @Test func putsEachHalfLinkInItsGroupAndKeepsAGroupThatHasOnlyHalfLinks() {

    let half = AllLinkGroupReading.HalfLink(endpoint: .modem, record: Self.record([.inUse, .usedBefore, .controller], group: 7, Self.plug))
    let reading = AllLinkGroupReading(
      groups: [AllLinkGroup(controller: .modem, number: Self.group(5), responders: [AllLinkGroup.Responder(.device(Self.lamp))])],
      halfLinks: [half], unreadable: [], unlisted: []
    )
    let listing = SceneListing(reading)

    #expect(listing.scenes.map(\.number) == [5, 7])
    #expect(listing.scenes[1].members.isEmpty)
    #expect(listing.scenes[1].halfLinks == [half])
    #expect(listing.scenes[0].halfLinks.isEmpty)

  }

  @Test func reportsTheDevicesItCouldNotReadOrDidNotKnowSoASceneIsNeverShownAsWhole() {

    let reading = AllLinkGroupReading(groups: [], halfLinks: [], unreadable: [Self.plug], unlisted: [Self.remote])
    let listing = SceneListing(reading)

    #expect(listing.unreadable == [Self.plug])
    #expect(listing.unlisted == [Self.remote])
    #expect(!listing.isWhole)
    #expect(SceneListing(AllLinkGroupReading(groups: [], halfLinks: [], unreadable: [], unlisted: [])).isWhole)

  }

  @Test func putsTheModemsScenesFirstInOrderThenTheDevicesOwn() {

    let reading = AllLinkGroupReading(
      groups: [
        AllLinkGroup(controller: .device(Self.remote), number: Self.group(1), responders: [AllLinkGroup.Responder(.device(Self.lamp))]),
        AllLinkGroup(controller: .modem, number: Self.group(9), responders: [AllLinkGroup.Responder(.device(Self.lamp))]),
        AllLinkGroup(controller: .modem, number: Self.group(2), responders: [AllLinkGroup.Responder(.device(Self.plug))])
      ],
      halfLinks: [], unreadable: [], unlisted: []
    )

    #expect(SceneListing(reading).scenes.map { "\($0.controller == .modem ? "modem" : "device")\($0.number)" } == ["modem2", "modem9", "device1"])

  }

  @Test func listsNothingForAnEmptyReading() {

    #expect(SceneListing(AllLinkGroupReading(groups: [], halfLinks: [], unreadable: [], unlisted: [])).scenes.isEmpty)

  }

}
