import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

// Linking a relay with a chosen state.
extension DeviceLinkingCoordinator {

  /// The operating flag that makes a relay momentary, such as an I/O Linc's: it closes for its
  /// momentary time, then opens again.
  static let momentaryFlag: SettingName = "momentary"

  /// The operating flag that makes both On and Off close a momentary relay.
  static let momentaryOnBothCommandsFlag: SettingName = "momentaryOnBothCommands"

  /// Links a relay as the modem's responder in one link, with the relay in a chosen state, so
  /// it records that state, as
  /// ``DeviceLinkingCoordinator/link(_:as:group:twoWay:setButtonTimeout:usesCatalogLegs:relayState:observer:)``
  /// describes.
  ///
  /// The steps, in order: the device's main group is checked to be a relay; its momentary flag
  /// is read; when it's on, it's turned off and read back, when the catalog lets linking change
  /// it, or else ``RelayStateLinkingError/momentaryNotChangeable(_:flag:)`` is thrown; the
  /// relay is set and confirmed; the device is linked; the flag is set back; and the observer
  /// is told what a group On and a group Off do.
  ///
  /// - Returns: The links made, the device, and what the group's commands do to the relay.
  /// - Throws: ``RelayStateLinkingError``, the errors of a link by address, and
  ///   `CancellationError` if the task is canceled.
  func link(
    _ device: InsteonAddress,
    recording state: RelayState,
    group: AllLinkGroupNumber,
    twoWay: TwoWayLinking,
    setButtonTimeout: Duration,
    observer: any LinkingObserver
  ) async throws -> DeviceLinkingResult {

    try await inTurn(changing: device) { () async throws -> DeviceLinkingResult in

      let description: DeviceDescription = try await relayDescription(of: device, observer: observer)
      let target: Device = network.device(device)
      let commands: CommandSet? = description.commandSet
      let momentary: OperatingFlag? = commands?.operatingFlag(named: Self.momentaryFlag)
      let bothCommands: OperatingFlag? = commands?.operatingFlag(named: Self.momentaryOnBothCommandsFlag)
      let flags: [SettingName: Bool] = try await read([momentary, bothCommands].compactMap { $0 }, of: target)
      let isMomentary: Bool = flags[Self.momentaryFlag] ?? false
      let writableFlags: Set<SettingName> = Self.writableLinkingFlags(of: description)

      if isMomentary, !writableFlags.contains(Self.momentaryFlag) {

        throw RelayStateLinkingError.momentaryNotChangeable(device, flag: Self.momentaryFlag.rawValue)

      }

      // The flag to set back once linking ends, however it ends.
      var cleared: OperatingFlag?

      do {

        if isMomentary, let momentary {

          await observer.linking(.relayState(.clearingFlag(device, flag: momentary.name.rawValue)))

          // Set first, so a failure or cancellation while it's written still sets it back.
          cleared = momentary

          try await Self.write(momentary, isSet: false, of: target, writableFlags: writableFlags)

        }

        try await setRelay(device, to: state, observer: observer)

        var result: DeviceLinkingResult = try await linkByAddress(
          device,
          as: .controller,
          group: group,
          twoWay: twoWay,
          setButtonTimeout: setButtonTimeout,
          description: description,
          observer: observer
        )
        var restoreFailure: (any Error)?

        if let flag = cleared {

          cleared = nil
          restoreFailure = await restore(flag, of: device, writableFlags: writableFlags, observer: observer)

        }

        let link = RelayStateLink(
          device: device,
          state: state,
          isMomentary: isMomentary,
          pulsesOnBothCommands: flags[Self.momentaryOnBothCommandsFlag] ?? false,
          restoreFailure: restoreFailure
        )

        await observer.linking(.relayState(.recorded(link)))
        result.relayState = link

        return result

      } catch {

        if let flag = cleared {

          // A failure to set it back is reported, and the error that stopped linking thrown.
          _ = await restore(flag, of: device, writableFlags: writableFlags, observer: observer)

        }

        throw error

      }

    }

  }

  /// What the catalog says about a device to be linked with a relay state, once it's checked
  /// to be a relay. A device the registry doesn't know is asked for its identity first.
  ///
  /// - Throws: ``RelayStateLinkingError/notDescribed(_:)`` or
  ///   ``RelayStateLinkingError/notARelay(_:product:)``, the errors of asking the device, and
  ///   `CancellationError` if the task is canceled.
  private func relayDescription(of device: InsteonAddress, observer: any LinkingObserver) async throws -> DeviceDescription {

    var description: DeviceDescription? = await network.registry.device(device)?.deviceDescription

    if description == nil {

      await observer.linking(.identifying(device))

      _ = try await network.identify(device)
      description = await network.registry.device(device)?.deviceDescription

    }

    guard let description, description.profile != nil else {

      throw RelayStateLinkingError.notDescribed(device)

    }

    guard description.mainGroupType?.kind == .relay else {

      throw RelayStateLinkingError.notARelay(device, product: DeviceControlModel.product(of: description))

    }

    return description

  }

  /// Reads operating flags with Get Operating Flags, each request once, however many flags
  /// its reply holds.
  ///
  /// - Returns: Whether each flag is set, by its name.
  /// - Throws: ``RelayStateLinkingError/flagUnreadable(_:flag:)`` for a reply that doesn't
  ///   carry a flag, and the modem's errors, such as `ModemError.deviceTimedOut`.
  private func read(_ flags: [OperatingFlag], of target: Device) async throws -> [SettingName: Bool] {

    var replies: [OperatingFlagsRequest: ReceivedMessage] = [:]
    var states: [SettingName: Bool] = [:]

    for flag in flags {

      let reply: ReceivedMessage

      if let known = replies[flag.query] {

        reply = known

      } else {

        reply = try await target.request(StandardMessage(to: target.address, command: flag.readCommand), timeout: network.requestTimeout, for: .control(.linkingFlags))
        replies[flag.query] = reply

      }

      guard let isSet = flag.isSet(in: reply) else {

        throw RelayStateLinkingError.flagUnreadable(target.address, flag: flag.name.rawValue)

      }

      states[flag.name] = isSet

    }

    return states

  }

  /// Writes an operating flag through the device's guarded send path, as linking may write
  /// it, and reads it back.
  ///
  /// - Throws: ``RelayStateLinkingError/flagNotChanged(_:flag:isSet:)`` when it reads back
  ///   otherwise, ``DeviceControlError`` when it's refused before anything is sent, and the
  ///   modem's errors.
  private static func write(_ flag: OperatingFlag, isSet: Bool, of target: Device, writableFlags: Set<SettingName>) async throws {

    let condition = DeviceProfile.Group.Condition(flag: flag.name, isSet: isSet)

    try await target.sendLinkingMessage(.flag(condition), duration: nil, writableFlags: writableFlags, for: .linkingFlags)

    let reply: ReceivedMessage = try await target.request(
      StandardMessage(to: target.address, command: flag.readCommand),
      timeout: target.network.requestTimeout,
      for: .control(.linkingFlags)
    )

    guard flag.isSet(in: reply) == isSet else {

      throw RelayStateLinkingError.flagNotChanged(target.address, flag: flag.name.rawValue, isSet: isSet)

    }

  }

  /// Puts the relay in the state and confirms it with its status: a relay already in the state
  /// isn't sent a command, and one that's sent Light On or Light Off is asked again.
  ///
  /// - Throws: ``RelayStateLinkingError/relayNotConfirmed(_:requested:)`` when its status
  ///   doesn't show the state afterward, the errors of reading its status, and the modem's
  ///   errors.
  private func setRelay(_ device: InsteonAddress, to state: RelayState, observer: any LinkingObserver) async throws {

    let target: Device = network.device(device)
    let isOn: Bool = state == .on

    if try await target.status().isOn == isOn {

      await observer.linking(.relayState(.relayAlreadySet(device, state)))

      return

    }

    await observer.linking(.relayState(.settingRelay(device, state)))

    try await makeLinker().prepareResponder(device, state: isOn ? .fullyOn : .off)

    guard try await target.status().isOn == isOn else {

      throw RelayStateLinkingError.relayNotConfirmed(device, requested: state)

    }

    await observer.linking(.relayState(.relayConfirmed(device, state)))

  }

  /// Sets a flag cleared for the link back on, and reads it back, to its end even when the
  /// task is canceled, and tells the observer how it went.
  ///
  /// - Returns: ``RelayStateLinkingError/flagNotRestored(_:flag:reason:)`` when it wasn't set
  ///   back, or `nil` when it was.
  private func restore(
    _ flag: OperatingFlag,
    of device: InsteonAddress,
    writableFlags: Set<SettingName>,
    observer: any LinkingObserver
  ) async -> (any Error)? {

    let target: Device = network.device(device)
    let name: String = flag.name.rawValue

    await observer.linking(.relayState(.restoringFlag(device, flag: name)))

    let failure: (any Error)? = await Self.runToEnd { () async -> (any Error)? in

      do {

        try await Self.write(flag, isSet: true, of: target, writableFlags: writableFlags)

        return nil

      } catch {

        return error

      }

    }

    guard let failure else {

      await observer.linking(.relayState(.flagRestored(device, flag: name)))

      return nil

    }

    await observer.linking(.relayState(.flagNotRestored(device, flag: name, reason: failure)))

    return RelayStateLinkingError.flagNotRestored(device, flag: name, reason: failure)

  }

}
