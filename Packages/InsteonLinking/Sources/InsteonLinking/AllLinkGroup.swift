import InsteonProtocol

/// An ALL-Link group: a controller's button or event, and the responders that act on it.
///
/// When the controller's button is pressed, it sends an ALL-Link broadcast to the group, and
/// every responder recalls the state it keeps for that group. Each responder's state is its
/// link data, such as a dimmer's on-level and ramp rate.
///
/// ```swift
/// let group = AllLinkGroup(
///   controller: .modem,
///   number: 0x05,
///   responders: [
///     .init(.device(lamp), data1: 0xFF, data2: 0x1F, data3: 0x01),
///     .init(.device(hallway), data1: 0x80, data2: 0x1C, data3: 0x01),
///   ]
/// )
/// ```
public struct AllLinkGroup: Hashable, Sendable {

  /// A responder in the group and the link data it keeps for it.
  ///
  /// What the data means depends on the responder. For a dimmer, `data1` is the on-level,
  /// `data2` the ramp rate, and `data3` the button or load the group controls.
  public struct Responder: Hashable, Sendable {

    /// The responder.
    public var endpoint: LinkEndpoint

    /// The first byte of link data, such as an on-level.
    public var data1: UInt8

    /// The second byte of link data, such as a ramp rate.
    public var data2: UInt8

    /// The third byte of link data, such as a button number.
    public var data3: UInt8

    /// Creates a responder.
    ///
    /// - Parameters:
    ///   - endpoint: The responder.
    ///   - data1: The first byte of link data. Defaults to `0x00`.
    ///   - data2: The second byte of link data. Defaults to `0x00`.
    ///   - data3: The third byte of link data. Defaults to `0x00`.
    public init(_ endpoint: LinkEndpoint, data1: UInt8 = 0x00, data2: UInt8 = 0x00, data3: UInt8 = 0x00) {

      self.endpoint = endpoint
      self.data1 = data1
      self.data2 = data2
      self.data3 = data3

    }

  }

  /// The controller whose button or event the group belongs to.
  public var controller: LinkEndpoint

  /// The group's number in the controller.
  public var number: AllLinkGroupNumber

  /// The responders in the group.
  public var responders: [Responder]

  /// Creates a group.
  ///
  /// - Parameters:
  ///   - controller: The controller whose button or event the group belongs to.
  ///   - number: The group's number in the controller.
  ///   - responders: The responders in the group. Defaults to none.
  public init(controller: LinkEndpoint, number: AllLinkGroupNumber, responders: [Responder] = []) {

    self.controller = controller
    self.number = number
    self.responders = responders

  }

}
