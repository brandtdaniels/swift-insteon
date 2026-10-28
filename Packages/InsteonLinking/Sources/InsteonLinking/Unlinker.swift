import InsteonModem
import InsteonProtocol

/// Removes the links between an ALL-Link group's controller and its responders.
///
/// The unlinker deletes each link's two records from the ALL-Link databases of the controller
/// and the responder, the reverse of ``Linker``. A device's record is deleted by clearing its
/// in-use bit, as the developer guide describes, so the space is reused by the next link.
///
/// ```swift
/// try await Unlinker(modem: modem).unlink(group)
/// ```
public struct Unlinker: Sendable {

  /// The modem the links were made through.
  public let modem: any LinkingModem

  /// How long to wait for each request to a device.
  public let timeout: Duration

  /// Creates an unlinker.
  ///
  /// - Parameters:
  ///   - modem: The modem the links were made through.
  ///   - timeout: How long to wait for each request to a device. Defaults to `Modem.defaultRequestTimeout`.
  public init(modem: any LinkingModem, timeout: Duration = Modem.defaultRequestTimeout) {

    self.modem = modem
    self.timeout = timeout

  }

  /// Removes the links between a group's controller and each of its responders.
  ///
  /// Links that aren't there are skipped, so unlinking a group that's partly linked removes
  /// what's left. Only the records for the group's number and endpoints are deleted; the
  /// devices' other links stay. The responders' link data doesn't matter.
  ///
  /// - Parameter group: The group to unlink.
  /// - Throws: ``LinkingError`` if a deleted record doesn't read back as written, or the
  ///   modem's errors.
  public func unlink(_ group: AllLinkGroup) async throws {

    var editor = DatabaseEditor(modem: modem, timeout: timeout)
    let addresses = try await editor.addresses(for: group)
    let controller = addresses.address(of: group.controller)

    for responder in group.responders {

      // The controller's record goes first, so the controller stops cleaning up with a
      // responder that no longer answers to the group.
      try await editor.delete(
        group: group.number,
        address: addresses.address(of: responder.endpoint),
        isController: true,
        from: group.controller
      )

      try await editor.delete(
        group: group.number,
        address: controller,
        isController: false,
        from: responder.endpoint
      )

    }

  }

}
