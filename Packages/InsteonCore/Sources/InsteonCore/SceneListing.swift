import InsteonLinking
import InsteonProtocol

/// The scenes of a home as a client sees them: each ALL-Link group some controller has members
/// for, listed from a reading of the modem's and the devices' ALL-Link databases.
///
/// A scene is a group the modem controls. A group a device controls, such as a button of a remote,
/// is listed too but can't be changed or run through the modem, so it is read only. The listing says
/// what the reading could not read, so an incomplete scene is never shown as whole.
///
/// ```swift
/// let listing = SceneListing(try await reader.read(devices: addresses))
/// for scene in listing.scenes where scene.isWritable {
///   print(scene.number, scene.members.map(\.address))
/// }
/// ```
public struct SceneListing: Hashable, Sendable {

  /// One device that responds to a scene, with the data bytes its record holds.
  public struct Member: Hashable, Sendable {

    /// The member's address.
    public var address: InsteonAddress

    /// The member's responder record's Data 1 through Data 3, which say what it does when the scene runs.
    public var data: [UInt8]

    /// Creates a member.
    ///
    /// - Parameters:
    ///   - address: The member's address.
    ///   - data: The three data bytes.
    public init(address: InsteonAddress, data: [UInt8]) {

      self.address = address
      self.data = data

    }

  }

  /// One scene: a group, who controls it, and who responds.
  public struct Scene: Hashable, Sendable {

    /// The group's number.
    public var number: UInt8

    /// Who controls the group.
    public var controller: LinkEndpoint

    /// The devices that respond to it, with each one's data bytes.
    public var members: [Member]

    /// The records whose other half is missing, so the link is not whole.
    public var halfLinks: [AllLinkGroupReading.HalfLink]

    /// Whether the modem can change and run the scene: the modem controls it, and it is a group
    /// from 1 through 254. Group 0 is the group linking uses by default, and 255 is reserved.
    public var isWritable: Bool {

      controller == .modem && (1...254).contains(number)

    }

    /// Creates a scene.
    ///
    /// - Parameters:
    ///   - number: The group's number.
    ///   - controller: Who controls it.
    ///   - members: The devices that respond to it.
    ///   - halfLinks: The records whose other half is missing.
    public init(number: UInt8, controller: LinkEndpoint, members: [Member] = [], halfLinks: [AllLinkGroupReading.HalfLink] = []) {

      self.number = number
      self.controller = controller
      self.members = members
      self.halfLinks = halfLinks

    }

  }

  /// The scenes: the modem's in order of number, then each device's in address and number order.
  public var scenes: [Scene]

  /// Devices whose ALL-Link database could not be read, so any scene they belong to may be missing them.
  public var unreadable: [InsteonAddress]

  /// Devices some record names that the reading had no list for, so the link is not checked.
  public var unlisted: [InsteonAddress]

  /// Whether the reading read every device and found no record without its other half.
  public var isWhole: Bool {

    unreadable.isEmpty && unlisted.isEmpty && scenes.allSatisfy { $0.halfLinks.isEmpty }

  }

  /// Lists the scenes of a reading.
  ///
  /// - Parameter reading: The reading of the ALL-Link databases.
  public init(_ reading: AllLinkGroupReading) {

    var scenes: [Scene] = reading.groups.map { (group: AllLinkGroup) -> Scene in

      Scene(
        number: group.number.rawValue,
        controller: group.controller,
        members: group.responders.compactMap { (responder: AllLinkGroup.Responder) -> Member? in

          guard case let .device(address) = responder.endpoint else { return nil }

          return Member(address: address, data: [responder.data1, responder.data2, responder.data3])

        }
      )

    }

    // A record of a controller whose other half is missing is a group of its own, even with no
    // member, so it can be seen and mended.
    for half in reading.halfLinks where half.record.flags.contains(.controller) {

      if !scenes.contains(where: { $0.controller == half.endpoint && $0.number == half.record.group.rawValue }) {

        scenes.append(Scene(number: half.record.group.rawValue, controller: half.endpoint))

      }

    }

    for index in scenes.indices {

      let scene: Scene = scenes[index]

      scenes[index].halfLinks = reading.halfLinks.filter { (half: AllLinkGroupReading.HalfLink) -> Bool in

        half.record.group.rawValue == scene.number && (!half.record.flags.contains(.controller) || half.endpoint == scene.controller)

      }

    }

    self.scenes = scenes.sorted(by: Self.ordered)
    self.unreadable = reading.unreadable
    self.unlisted = reading.unlisted

  }

  /// Creates a listing.
  ///
  /// - Parameters:
  ///   - scenes: The scenes.
  ///   - unreadable: Devices whose database could not be read.
  ///   - unlisted: Devices the reading had no list for.
  public init(scenes: [Scene], unreadable: [InsteonAddress] = [], unlisted: [InsteonAddress] = []) {

    self.scenes = scenes
    self.unreadable = unreadable
    self.unlisted = unlisted

  }

  private static func ordered(_ first: Scene, _ second: Scene) -> Bool {

    switch (first.controller, second.controller) {
    case (.modem, .modem):
      return first.number < second.number
    case (.modem, .device):
      return true
    case (.device, .modem):
      return false
    case let (.device(one), .device(two)):
      return one == two ? first.number < second.number : one.bytes.lexicographicallyPrecedes(two.bytes)
    }

  }

}
