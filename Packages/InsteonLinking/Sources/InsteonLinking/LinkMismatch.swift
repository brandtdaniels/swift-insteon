import InsteonProtocol

/// Whether a link is being made or removed.
public enum LinkingDirection: Hashable, Sendable {

  /// A link is being made.
  case linking

  /// A link is being removed.
  case unlinking

}

/// A link the modem reported that isn't the one asked for: another device's, or a link made
/// where one was to be removed, or the reverse.
///
/// While the modem is in linking or unlinking mode, any device whose SET button is pressed can
/// link to it, and a device a person puts into the wrong mode links where it was to unlink, or
/// unlinks where it was to link. The modem reports what happened either way, so a manual link
/// or unlink checks the report and throws this error, which says which mistake it was:
///
/// ```swift
/// do {
///   try await Linker(modem: modem).linkManually(as: .controller, group: 0, device: lamp)
/// } catch let mismatch as LinkMismatch {
///   switch mismatch.reason {
///   case let .otherDevice(expected): print("\(mismatch.link.address) linked, not \(expected)")
///   case .unlinkedInsteadOfLinking: print("Hold the SET button only until the device first beeps.")
///   case .linkedInsteadOfUnlinking: print("Put the device into unlinking mode.")
///   }
/// }
/// ```
public struct LinkMismatch: Error, Hashable, Sendable {

  /// What's wrong with a link the modem reported.
  public enum Reason: Hashable, Sendable {

    /// Another device linked or unlinked: its SET button was pressed while the modem waited.
    /// The value is the device that was asked for.
    case otherDevice(expected: InsteonAddress)

    /// The device linked where a link was to be removed: it was in linking mode, not
    /// unlinking mode.
    case linkedInsteadOfUnlinking

    /// The device removed its link where one was to be made: it was in unlinking mode, not
    /// linking mode.
    case unlinkedInsteadOfLinking

  }

  /// The link the modem reported.
  public var link: AllLinkingCompleted

  /// What's wrong with it.
  public var reason: Reason

  /// Creates a mismatch.
  ///
  /// - Parameters:
  ///   - link: The link the modem reported.
  ///   - reason: What's wrong with it.
  public init(link: AllLinkingCompleted, reason: Reason) {

    self.link = link
    self.reason = reason

  }

  /// Checks a link the modem reported against the one asked for.
  ///
  /// Another device is reported first, since its link says nothing about the device asked
  /// for. The modem reports a removed link with `AllLinkMode.delete`, and a new one with its
  /// role.
  ///
  /// - Parameters:
  ///   - link: The link the modem reported.
  ///   - direction: Whether a link was being made or removed.
  ///   - device: The device asked for, or `nil` for any device.
  /// - Returns: `nil` if the link is the one asked for.
  public init?(_ link: AllLinkingCompleted, direction: LinkingDirection, device: InsteonAddress?) {

    if let device, link.address != device {

      self.init(link: link, reason: .otherDevice(expected: device))

      return

    }

    let removed: Bool = link.mode == .delete

    switch direction {
    case .unlinking where !removed:
      self.init(link: link, reason: .linkedInsteadOfUnlinking)
    case .linking where removed:
      self.init(link: link, reason: .unlinkedInsteadOfLinking)
    case .linking, .unlinking:
      return nil
    }

  }

}
