import InsteonModem
import InsteonProtocol

/// Links an ALL-Link group's controller to its responders.
///
/// The linker writes each link's two records directly into the ALL-Link databases of the
/// controller and the responder: a controller record in the controller, and a responder record
/// holding the responder's link data in the responder. Writing the records sets each
/// responder's link data exactly, where linking with the SET button records whatever state the
/// responder is in at the time.
///
/// Devices with an i2 or i2cs engine accept database writes. An i2cs device accepts them only
/// from a modem it's already linked to, and rejects them with `NAKReason.notLinked`
/// otherwise. i1 devices don't have database writes.
///
/// ```swift
/// let linker = Linker(modem: modem)
///
/// try await linker.link(AllLinkGroup(
///   controller: .modem,
///   number: 0x05,
///   responders: [.init(.device(lamp), data1: 0xFF, data2: 0x1F, data3: 0x01)]
/// ))
/// ```
public struct Linker: Sendable {

  /// The modem the links are made through.
  public let modem: any LinkingModem

  /// How long to wait for each request to a device.
  public let timeout: Duration

  /// Creates a linker.
  ///
  /// - Parameters:
  ///   - modem: The modem the links are made through.
  ///   - timeout: How long to wait for each request to a device. Defaults to `Modem.defaultRequestTimeout`.
  public init(modem: any LinkingModem, timeout: Duration = Modem.defaultRequestTimeout) {

    self.modem = modem
    self.timeout = timeout

  }

  /// Links a group's controller to each of its responders by writing their records.
  ///
  /// A responder record that already links the same devices in the same group is updated with
  /// the group's link data, so linking a group again changes its responders' data in place. A
  /// controller record that's already there stays as it is, since its data belongs to the
  /// controller; a new one has all-zero data. Links are made one responder at a time, each
  /// responder's record before the controller's, and those already made stay made if a later
  /// one fails.
  ///
  /// - Parameter group: The group to link.
  /// - Throws: ``LinkingError`` if a device's database is full or a record doesn't read back
  ///   as written, or the modem's errors, such as `ModemError.deviceRejected` from an i2cs
  ///   device that isn't linked to the modem.
  public func link(_ group: AllLinkGroup) async throws {

    var editor = DatabaseEditor(modem: modem, timeout: timeout)
    let addresses = try await editor.addresses(for: group)
    let controller = addresses.address(of: group.controller)

    for responder in group.responders {

      // The responder's record goes first, so a responder that rejects it, such as an i2cs
      // device that isn't linked to the modem, doesn't leave the controller with a link to it.
      try await editor.write(
        AllLinkRecord(
          flags: DatabaseEditor.flags(isController: false),
          group: group.number,
          address: controller,
          data1: responder.data1,
          data2: responder.data2,
          data3: responder.data3
        ),
        into: responder.endpoint
      )

      try await editor.write(
        AllLinkRecord(
          flags: DatabaseEditor.flags(isController: true),
          group: group.number,
          address: addresses.address(of: responder.endpoint)
        ),
        into: group.controller
      )

    }

  }

}
