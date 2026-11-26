import InsteonLinking
import InsteonProtocol

/// The scenes of a network as a client sees them: each ALL-Link group some controller has members
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

    /// The devices that respond to it, with each one's data bytes. The modem itself, when it
    /// responds to a group a device controls, is not listed, and a device with two records for the
    /// group is listed twice with each record's bytes.
    public var members: [Member]

    /// The records whose other half is missing, so the link is not whole.
    public var halfLinks: [AllLinkGroupReading.HalfLink]

    /// Whether the modem can change and run the scene: the modem controls it, and it is a group
    /// from 1 through 254. Group 0 is the group `insteon link` uses by default, and 255 is
    /// `AllLinkGroupNumber.all`, which addresses every group, so neither is a scene the modem
    /// is asked to change or run.
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

  /// Records whose other half is missing and that no scene of their group number holds, such as a
  /// device's responder record for a group nothing lists.
  public var looseHalfLinks: [AllLinkGroupReading.HalfLink]

  /// Devices whose ALL-Link database could not be read, so any scene they belong to may be missing them.
  public var unreadable: [InsteonAddress]

  /// Why each device in ``unreadable`` could not be read, where the reading knows. A device with no
  /// entry has no copy of its database and no recorded attempt; ``unreadableReason(of:)`` says
  /// ``BackupUnreadableReason/notCached`` for it.
  public var unreadableReasons: [InsteonAddress: BackupUnreadableReason]

  /// Devices some record names that the reading had no list for, so the link is not checked.
  public var unlisted: [InsteonAddress]

  /// Why a device's database could not be read.
  ///
  /// - Parameter address: A device in ``unreadable``.
  /// - Returns: The recorded reason, or ``BackupUnreadableReason/notCached`` when none is recorded.
  public func unreadableReason(of address: InsteonAddress) -> BackupUnreadableReason {

    unreadableReasons[address] ?? .notCached

  }

  /// Whether the modem's own database was not held, so no scene is listed from it.
  public var isModemUnread: Bool

  /// Whether the reading read every device and found no record without its other half.
  public var isWhole: Bool {

    !isModemUnread && unreadable.isEmpty && unlisted.isEmpty && looseHalfLinks.isEmpty && scenes.allSatisfy { $0.halfLinks.isEmpty }

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

        guard half.record.group.rawValue == scene.number else { return false }

        // A controller record belongs to the group of the endpoint that holds it. A responder
        // record belongs to the group of the controller it names: a device that some scene lists
        // as controlling, or otherwise the modem, whose address the reading doesn't carry.
        if half.record.flags.contains(.controller) {

          return half.endpoint == scene.controller

        }

        let names: LinkEndpoint = .device(half.record.address)
        let isListedDevice: Bool = scenes.contains { $0.controller == names && $0.number == scene.number }

        return isListedDevice ? scene.controller == names : scene.controller == .modem

      }

    }

    let ordered: [Scene] = scenes.sorted(by: Self.ordered)

    self.scenes = ordered
    self.looseHalfLinks = reading.halfLinks.filter { (half: AllLinkGroupReading.HalfLink) -> Bool in !ordered.contains { $0.halfLinks.contains(half) } }
    self.unreadable = reading.unreadable
    self.unreadableReasons = [:]
    self.unlisted = reading.unlisted
    self.isModemUnread = false

  }

  /// Creates a listing.
  ///
  /// - Parameters:
  ///   - scenes: The scenes.
  ///   - looseHalfLinks: Records no scene holds whose other half is missing.
  ///   - unreadable: Devices whose database could not be read.
  ///   - unreadableReasons: Why, for each device that has a recorded reason.
  ///   - unlisted: Devices the reading had no list for.
  ///   - isModemUnread: Whether the modem's database was not held.
  public init(scenes: [Scene], looseHalfLinks: [AllLinkGroupReading.HalfLink] = [], unreadable: [InsteonAddress] = [], unreadableReasons: [InsteonAddress: BackupUnreadableReason] = [:], unlisted: [InsteonAddress] = [], isModemUnread: Bool = false) {

    self.isModemUnread = isModemUnread
    self.scenes = scenes
    self.looseHalfLinks = looseHalfLinks
    self.unreadable = unreadable
    self.unreadableReasons = unreadableReasons
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
