import Testing
import InsteonProtocol

struct ProductTests {

  let device = InsteonAddress(0xCC, 0xCC, 0xCC)

  let modem = InsteonAddress(0x11, 0x22, 0x33)

  func broadcast(to destination: InsteonAddress, command1: UInt8) -> ReceivedMessage {

    ReceivedMessage(
      sender: device,
      destination: destination,
      flags: MessageFlags(messageType: .broadcast),
      command: Command(command1: command1, command2: 0xFF)
    )

  }

  // The guide's example: a device with DevCat 0x01 and SubCat 0x03 that reports no firmware.
  @Test func readsSetButtonPressedFromTheToAddress() throws {

    let identity = try #require(SetButtonPressed(broadcast(to: InsteonAddress(0x01, 0x03, 0xFF), command1: 0x01)))

    #expect(identity == SetButtonPressed(sender: device, role: .responder, category: 0x01, subcategory: 0x03, firmwareVersion: nil))

  }

  @Test func readsTheFirmwareVersionWhenTheDeviceReportsOne() throws {

    let identity = try #require(SetButtonPressed(broadcast(to: InsteonAddress(0x02, 0x2A, 0x41), command1: 0x02)))

    #expect(identity.role == .controller)
    #expect(identity.firmwareVersion == 0x41)

  }

  @Test(arguments: [
    // Another broadcast command.
    ReceivedMessage(
      sender: InsteonAddress(0xCC, 0xCC, 0xCC),
      destination: InsteonAddress(0x01, 0x03, 0xFF),
      flags: MessageFlags(messageType: .broadcast),
      command: Command(command1: 0x03)
    ),
    // A direct message with cmd1 0x01.
    ReceivedMessage(
      sender: InsteonAddress(0xCC, 0xCC, 0xCC),
      destination: InsteonAddress(0x11, 0x22, 0x33),
      flags: MessageFlags(messageType: .direct),
      command: Command(command1: 0x01)
    ),
    // An extended broadcast.
    ReceivedMessage(
      sender: InsteonAddress(0xCC, 0xCC, 0xCC),
      destination: InsteonAddress(0x01, 0x03, 0xFF),
      flags: MessageFlags(messageType: .broadcast, isExtended: true),
      command: Command(command1: 0x01)
    ),
  ])
  func ignoresOtherMessagesAsSetButtonPressed(_ message: ReceivedMessage) {

    #expect(SetButtonPressed(message) == nil)

  }

  @Test func readsProductDataFromTheUserData() throws {

    let userData = try UserData([0x00, 0x00, 0x00, 0x34, 0x00, 0x05, 0xFF, 0xFF, 0x41, 0, 0, 0, 0, 0])
    let message = ReceivedMessage(
      sender: device,
      destination: modem,
      flags: .extendedDirect,
      command: Command(command1: 0x03, command2: 0x00),
      userData: userData
    )

    let product = try #require(ProductData(message))

    #expect(product.category == 0x00)
    #expect(product.subcategory == 0x05)
    #expect(product.userDefined == [0x41, 0, 0, 0, 0, 0])

  }

  // cmd2 0x02 asks for the device's text string, which also arrives with cmd1 0x03.
  @Test func ignoresOtherResponsesWithTheSameCommand() throws {

    let message = ReceivedMessage(
      sender: device,
      destination: modem,
      flags: .extendedDirect,
      command: Command(command1: 0x03, command2: 0x02),
      userData: try UserData(Array("Kitchen".utf8))
    )

    #expect(ProductData(message) == nil)

  }

  @Test func ignoresStandardMessagesAsProductData() {

    let message = ReceivedMessage(sender: device, destination: modem, flags: .direct, command: Command(command1: 0x03))

    #expect(ProductData(message) == nil)

  }

  @Test func printsIdentityBytesInHex() {

    #expect(DeviceCategory(rawValue: 0x0E).description == "0x0E")
    #expect(DeviceSubcategory(rawValue: 0x2A).description == "0x2A")
    #expect(FirmwareVersion(rawValue: 0x41).description == "0x41")

  }

  // The names in the developer guide's table of device categories.
  @Test(arguments: [
    (DeviceCategory.generalizedControllers, UInt8(0x00), "Generalized Controllers"),
    (.dimmableLightingControl, 0x01, "Dimmable Lighting Control"),
    (.networkBridges, 0x03, "Network Bridges"),
    (.securityHealthSafety, 0x10, "Security, Health, Safety"),
    (.holiday, 0x16, "Holiday"),
    (.unassigned, 0xFF, "Unassigned")
  ])
  func namesTheGuidesCategories(_ category: DeviceCategory, _ number: UInt8, _ name: String) {

    #expect(category.rawValue == number)
    #expect(category.name == name)

  }

  @Test func leavesReservedCategoriesUnnamed() {

    #expect(DeviceCategory(rawValue: 0x17).name == nil)
    #expect(DeviceCategory(rawValue: 0xFE).name == nil)

  }

  @Test func ordersFirmwareVersionsByNumber() {

    #expect(FirmwareVersion(rawValue: 0x40) < 0x41)
    #expect([FirmwareVersion(rawValue: 0x45), 0x41, 0x43].max() == 0x45)

  }

  @Test func encodesTheHostDeviceCategory() {

    #expect(SerialCommand.setHostDeviceCategory(category: 0x03, subcategory: 0x15, firmwareVersion: 0x41).bytes == [0x02, 0x66, 0x03, 0x15, 0x41])
    // No firmware version is sent as 0xFF.
    #expect(SerialCommand.setHostDeviceCategory(category: 0x03, subcategory: 0x15, firmwareVersion: nil).bytes == [0x02, 0x66, 0x03, 0x15, 0xFF])

  }

}
