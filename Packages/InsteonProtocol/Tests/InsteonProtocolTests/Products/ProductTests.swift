import Testing
import InsteonProtocol

struct ProductTests {

  let device = InsteonAddress(0xCC, 0xCC, 0xCC)

  let modem = InsteonAddress(0x11, 0x22, 0x33)

  func broadcast(to destination: InsteonAddress, command1: UInt8, isExtended: Bool = false) -> ReceivedMessage {

    ReceivedMessage(
      sender: device,
      destination: destination,
      flags: MessageFlags(messageType: .broadcast, isExtended: isExtended),
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

  @Test func ignoresStandardMessagesAsProductData() {

    let message = ReceivedMessage(sender: device, destination: modem, flags: .direct, command: Command(command1: 0x03))

    #expect(ProductData(message) == nil)

  }

  @Test func printsCategoriesInHex() {

    #expect(DeviceCategory(rawValue: 0x0E).description == "0x0E")

  }

  @Test func encodesTheHostDeviceCategory() {

    #expect(SerialCommand.setHostDeviceCategory(category: 0x03, subcategory: 0x15, firmwareVersion: 0xFF).bytes == [0x02, 0x66, 0x03, 0x15, 0xFF])

  }

  @Test func capabilitiesDependOnTheFirmwareVersion() async throws {

    let database = FirmwareDependentDatabase()

    let early = try #require(try await database.capabilities(category: 0x01, subcategory: 0x20, firmwareVersion: 0x40))
    let later = try #require(try await database.capabilities(category: 0x01, subcategory: 0x20, firmwareVersion: 0x41))

    #expect(early.responds(to: StandardDirectCommand.on(level: 0xFF)))
    #expect(!early.responds(to: StandardDirectCommand.beep))
    #expect(later.responds(to: StandardDirectCommand.beep))
    #expect(try await database.capabilities(category: 0x02, subcategory: 0x20, firmwareVersion: nil) == nil)

  }

}

/// Capabilities matched by cmd1, as a product database might record them.
private struct CommandList: DeviceCapabilities {

  let respondedCommands: Set<UInt8>

  func responds(to command: Command) -> Bool { respondedCommands.contains(command.command1) }

  func sends(_ command: Command) -> Bool { false }

}

/// A database where firmware 0x41 of one product adds the beep command.
private struct FirmwareDependentDatabase: ProductDatabase {

  func capabilities(category: DeviceCategory, subcategory: UInt8, firmwareVersion: UInt8?) async throws -> (any DeviceCapabilities)? {

    guard category == 0x01, subcategory == 0x20 else { return nil }

    return (firmwareVersion ?? 0) >= 0x41 ? CommandList(respondedCommands: [0x11, 0x13, 0x30]) : CommandList(respondedCommands: [0x11, 0x13])

  }

}
