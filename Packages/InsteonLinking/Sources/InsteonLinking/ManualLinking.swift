import InsteonProtocol

/// The modem's role in a link made with a device's SET button, which can leave the choice to
/// the device.
public enum ManualLinkingRole: Hashable, Sendable {

  /// The modem controls the device: the device joins one of the modem's ALL-Link groups.
  case controller

  /// The modem responds to the device: the modem joins one of the device's ALL-Link groups.
  /// Put the device into linking mode first, so it's waiting as the controller when the
  /// modem joins.
  case responder

  /// The modem controls the device or responds to it, whichever the device asks for: it
  /// responds to a device that's already in linking mode, and controls one that enters
  /// linking mode after it.
  case either

  /// The role a ``ModemRole`` names.
  ///
  /// - Parameter role: The modem's role.
  public init(_ role: ModemRole) {

    switch role {
    case .controller: self = .controller
    case .responder: self = .responder
    }

  }

  /// The modem's linking mode for the role.
  var linkingMode: AllLinkMode {

    switch self {
    case .controller: .controller
    case .responder: .responder
    case .either: .controllerOrResponder
    }

  }

}

extension Linker {

  /// Puts the modem into linking mode, says when it's ready, and waits for someone to press a
  /// device's SET button.
  ///
  /// This works with devices of every engine. `ready` runs once the modem is in linking
  /// mode, which is when to tell a person to press the SET button. With
  /// ``ManualLinkingRole/responder``, put the device into linking mode first, then call this.
  ///
  /// Whichever link the modem reports ends the wait, and is then checked. The modem leaves
  /// linking mode on its own once it reports a link; when none arrives in time, or the task
  /// is canceled, it's taken out of linking mode before this returns.
  ///
  /// ```swift
  /// let link = try await Linker(modem: modem).linkManually(as: .either, group: 0) {
  ///   print("Press and hold the device's SET button until it beeps.")
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - role: The modem's role, or ``ManualLinkingRole/either``.
  ///   - group: The modem's group.
  ///   - device: The device whose link to accept, or `nil` for any device.
  ///   - linkingTimeout: How long to wait. Defaults to ``Linker/defaultManualLinkingTimeout``.
  ///   - ready: Called once the modem is in linking mode.
  /// - Returns: The link the modem reports, including the device's address.
  /// - Throws: ``LinkingError/linkingTimedOut`` if no device links in time,
  ///   ``LinkingError/unexpectedLink(_:)`` if the modem controls the link it reports in
  ///   another group than asked, ``LinkMismatch`` if another device linked or the device
  ///   removed its link instead, or the modem's errors, such as `CancellationError`.
  @discardableResult
  public func linkManually(
    as role: ManualLinkingRole,
    group: AllLinkGroupNumber,
    device: InsteonAddress? = nil,
    timeout linkingTimeout: Duration = Linker.defaultManualLinkingTimeout,
    ready: @escaping @Sendable () async -> Void = {}
  ) async throws -> AllLinkingCompleted {

    try await LinkingSession(modem: modem, timeout: timeout, clock: clock, cache: cache).manual(
      modemMode: role.linkingMode,
      group: group,
      direction: .linking,
      device: device,
      within: linkingTimeout,
      ready: ready
    )

  }

}

extension Unlinker {

  /// Puts the modem into its mode for removing a link, says when it's ready, and waits for
  /// someone to press a device's SET button.
  ///
  /// When the modem is the controller, it enters unlinking mode, and the device's SET button
  /// is pressed as for linking. When the modem is the responder, put the device into
  /// unlinking mode with its SET button first, then call this; the modem joins in linking
  /// mode as the responder. `ready` runs once the modem is in its mode.
  ///
  /// Whichever link the modem reports ends the wait, and is then checked. When none arrives
  /// in time, or the task is canceled, the modem is taken out of its mode before this
  /// returns.
  ///
  /// - Parameters:
  ///   - role: Whether the modem controls the device or responds to it.
  ///   - group: The modem's group in the link.
  ///   - device: The device whose unlink to accept, or `nil` for any device.
  ///   - linkingTimeout: How long to wait. Defaults to `Linker.defaultManualLinkingTimeout`.
  ///   - ready: Called once the modem is in its mode.
  /// - Returns: The removed link the modem reports, including the device's address.
  /// - Throws: ``LinkingError/linkingTimedOut`` if no device unlinks in time,
  ///   ``LinkingError/unexpectedLink(_:)`` if the modem, as the controller, reports another
  ///   group than asked, ``LinkMismatch`` if another device unlinked or the device linked
  ///   instead, or the modem's errors, such as `CancellationError`.
  @discardableResult
  public func unlinkManually(
    as role: ModemRole,
    group: AllLinkGroupNumber,
    device: InsteonAddress? = nil,
    timeout linkingTimeout: Duration = Linker.defaultManualLinkingTimeout,
    ready: @escaping @Sendable () async -> Void = {}
  ) async throws -> AllLinkingCompleted {

    try await LinkingSession(modem: modem, timeout: timeout, clock: clock, cache: cache).manual(
      modemMode: role.unlinkingMode,
      group: group,
      direction: .unlinking,
      device: device,
      within: linkingTimeout,
      ready: ready
    )

  }

}
