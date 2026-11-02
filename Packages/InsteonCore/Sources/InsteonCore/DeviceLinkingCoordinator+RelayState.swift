import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

// Linking a relay with a chosen state.
extension DeviceLinkingCoordinator {

  /// The operating flag that makes a relay momentary, such as an I/O Linc's: it closes for its
  /// momentary time, then opens again, so it can't hold a state to record.
  ///
  /// The catalog names a flag's meaning only in words, and its ``CommandSet/linkingChanges``
  /// says which flags linking may change, not why, so the flag is found by the name the
  /// catalog's I/O Linc command set gives it.
  static let momentaryFlag: SettingName = "momentary"

  /// The operating flag that makes both On and Off close a momentary relay, found by name for
  /// the same reason as ``momentaryFlag``.
  static let momentaryOnBothCommandsFlag: SettingName = "momentaryOnBothCommands"

  /// Links a relay, such as an I/O Linc's, by its address so it records a chosen state: a
  /// group On from the modem then sets the relay to it, and a group Off to the opposite.
  ///
  /// The modem is the controller, and the device's main group must be a relay, as the
  /// catalog describes it. A device the registry doesn't know is asked for its identity with
  /// ID Request first. Then, in order:
  ///
  /// 1. The relay's operating flags are read with Get Operating Flags, and its status with
  ///    the command its group type names. A device that rejects the modem, as an i2CS device
  ///    does until it holds a link to it, is refused here.
  /// 2. When the relay isn't in the state, or is momentary and the state is on, it must be
  ///    sent a command. A momentary relay would open again before it links, so its momentary
  ///    flag is turned off first and read back, but only when the catalog's linking changes
  ///    allow it; otherwise the link is refused. A relay already in the state is sent nothing,
  ///    and no flag is written.
  /// 3. The relay is sent its group type's On or Off through the device's guarded send path,
  ///    and its status is read again; a relay that doesn't show the state isn't linked.
  /// 4. The device is linked in one link, in the modem's `group`, not by the catalog's legs.
  ///    A device that doesn't link without its SET button isn't linked with it, since that
  ///    records whatever state the relay is in by the time a person presses it.
  /// 5. The relay's responder record is read back, and its Data 1 compared with the state.
  /// 6. A momentary relay that was switched is switched back to its state before the link,
  ///    while its flag is still off, so it isn't left closed; then the flag is turned back on
  ///    and read back, once more if that fails, and the whole flags byte compared with the one
  ///    read first.
  ///
  /// Step 6 runs however linking ends, after a failure and when the task is canceled. The
  /// observer gets ``LinkingEvent/relayState(_:)`` for each step, and the result's
  /// ``DeviceLinkingResult/relayState`` says what a group On and a group Off do, and what
  /// didn't go as asked once the link was made, which doesn't throw.
  ///
  /// ```swift
  /// let result = try await network.linking.linkRelay(module, recording: .off, group: 2, observer: prompter)
  ///
  /// for problem in result.relayState?.problems ?? [] {
  ///   print(problem)
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - device: The relay.
  ///   - state: The state it records.
  ///   - group: The modem's group. Defaults to ``DeviceLinkingCoordinator/defaultModemGroup``.
  ///   - twoWay: Whether to link the device back. Defaults to
  ///     ``TwoWayLinking/whenDeviceControls``.
  ///   - setButtonTimeout: How long the modem waits in linking mode for a link back. Defaults
  ///     to ``defaultSETButtonTimeout``.
  ///   - observer: What a person is told.
  /// - Returns: The links made, the device, and the relay's ``RelayStateLink``.
  /// - Throws: ``RelayStateLinkingError`` when the relay can't record the state or doesn't
  ///   link without its SET button, `LinkMismatch` or `LinkingError.unexpectedLink(_:)` when
  ///   the modem reports another link, the modem's errors, such as
  ///   `ModemError.deviceTimedOut` when the device doesn't answer, and `CancellationError` if
  ///   the task is canceled.
  public func linkRelay(
    _ device: InsteonAddress,
    recording state: RelayState,
    group: AllLinkGroupNumber = DeviceLinkingCoordinator.defaultModemGroup,
    twoWay: TwoWayLinking = .whenDeviceControls,
    setButtonTimeout: Duration = Linker.defaultManualLinkingTimeout,
    observer: any LinkingObserver
  ) async throws -> DeviceLinkingResult {

    // The device's databases are recorded as changed only once a link may have been made, so
    // a refusal leaves the network's copies as they are.
    try await inTurn(changing: nil) { () async throws -> DeviceLinkingResult in

      let description: DeviceDescription = try await relayDescription(of: device, observer: observer)
      let target: Device = network.device(device)
      let commands: CommandSet? = description.commandSet
      let momentary: OperatingFlag? = commands?.operatingFlag(named: Self.momentaryFlag)
      let bothCommands: OperatingFlag? = commands?.operatingFlag(named: Self.momentaryOnBothCommandsFlag)
      let flags: RelayFlags = try await readFlags([momentary, bothCommands].compactMap { $0 }, of: target)
      let isMomentary: Bool = flags.states[Self.momentaryFlag] ?? false
      let before: RelayState = try await rejectingUnlinked(device) { () async throws -> Bool in try await target.status().isOn } ? .on : .off
      // A momentary relay reads on only while it's closed for its momentary time, so it's
      // held on with a command of its own.
      let needsCommand: Bool = before != state || (isMomentary && state == .on)
      let writableFlags: Set<SettingName> = Self.writableLinkingFlags(of: description)

      if isMomentary, needsCommand, !writableFlags.contains(Self.momentaryFlag) {

        throw RelayStateLinkingError.momentaryNotChangeable(device, flag: Self.momentaryFlag.rawValue)

      }

      // What to put back however linking ends: the flag turned off, and the relay's state
      // before the link when it was switched.
      var cleared: OperatingFlag?
      var switched: Bool = false

      do {

        if isMomentary, needsCommand, let momentary {

          await observer.linking(.relayState(.clearingFlag(device, flag: momentary.name.rawValue)))

          do {

            try await Self.write(momentary, isSet: false, of: target, writableFlags: writableFlags)

          } catch let error as DeviceControlError {

            // Refused before anything was sent, so there's nothing to put back.
            throw error

          } catch let error as FieldError {

            throw error

          } catch {

            // The message may have reached the device.
            cleared = momentary

            throw error

          }

          cleared = momentary

          guard try await Self.read(momentary, of: target).command.command2 & momentary.bit == 0 else {

            throw RelayStateLinkingError.flagNotChanged(device, flag: momentary.name.rawValue, isSet: false)

          }

        }

        if needsCommand {

          await observer.linking(.relayState(.settingRelay(device, state)))

          // Set first: the relay may have switched though its acknowledgment was lost.
          switched = true

          try await Self.switchRelay(target, to: state)

          guard try await target.status().isOn == (state == .on) else {

            throw RelayStateLinkingError.relayNotConfirmed(device, requested: state)

          }

          await observer.linking(.relayState(.relayConfirmed(device, state)))

        } else {

          await observer.linking(.relayState(.relayAlreadySet(device, state)))

        }

        var result: DeviceLinkingResult = try await link(device, group: group, twoWay: twoWay, setButtonTimeout: setButtonTimeout, description: description, observer: observer)
        let linkedGroup: AllLinkGroupNumber = result.links.first?.group ?? group
        let recorded: (data1: UInt8?, failure: RelayStateLinkingError?) = try await checkRecord(of: device, group: linkedGroup, state: state)
        var restored: Restored = Restored(isMomentary: isMomentary, failures: [])

        if let flag = cleared {

          cleared = nil
          restored = await putBack(flag, relayTo: switched ? before : nil, of: target, originalFlags: flags.bytes[flag.query], writableFlags: writableFlags, observer: observer)

        }

        let link = RelayStateLink(
          device: device,
          state: state,
          group: linkedGroup,
          recordedData1: recorded.data1,
          recordFailure: recorded.failure,
          clearedFlag: isMomentary && needsCommand ? momentary?.name.rawValue : nil,
          isMomentary: restored.isMomentary,
          pulsesOnBothCommands: flags.states[Self.momentaryOnBothCommandsFlag] ?? false,
          restoreFailures: restored.failures
        )

        await observer.linking(.relayState(.recorded(link)))
        result.relayState = link

        return result

      } catch {

        if let flag = cleared {

          // What put back didn't go as it was is reported, and the error that stopped
          // linking thrown.
          _ = await putBack(flag, relayTo: switched ? before : nil, of: target, originalFlags: flags.bytes[flag.query], writableFlags: writableFlags, observer: observer)

        }

        throw error

      }

    }

  }

  /// The operating flags a relay reported, read once per Get Operating Flags request.
  private struct RelayFlags {

    /// Whether each flag is set, by its name.
    var states: [SettingName: Bool] = [:]

    /// The whole byte each request reported.
    var bytes: [OperatingFlagsRequest: UInt8] = [:]

  }

  /// How putting back what linking changed went.
  private struct Restored: Sendable {

    /// Whether the relay is momentary afterward, as its flag read back.
    var isMomentary: Bool

    /// What didn't go back as it was.
    var failures: [RelayStateLinkingError]

  }

  /// What the catalog says about a device to be linked with a relay state, once it's checked
  /// to be a relay. A device the registry doesn't know is asked for its identity first.
  ///
  /// - Throws: ``RelayStateLinkingError/notIdentified(_:because:)``,
  ///   ``RelayStateLinkingError/notLinkedToModem(_:)``,
  ///   ``RelayStateLinkingError/notDescribed(_:)`` or
  ///   ``RelayStateLinkingError/notARelay(_:product:)``, and `CancellationError` if the task
  ///   is canceled.
  private func relayDescription(of device: InsteonAddress, observer: any LinkingObserver) async throws -> DeviceDescription {

    var description: DeviceDescription? = await network.registry.device(device)?.deviceDescription

    if description == nil {

      let identified: (description: DeviceDescription?, reason: UnidentifiedReason?) = try await askIdentity(of: device, observer: observer)

      switch identified.reason {
      case .notLinked?:
        throw RelayStateLinkingError.notLinkedToModem(device)
      case let reason?:
        throw RelayStateLinkingError.notIdentified(device, because: reason)
      case nil:
        description = identified.description
      }

    }

    guard let description, description.profile != nil else {

      throw RelayStateLinkingError.notDescribed(device)

    }

    guard description.mainGroupType?.kind == .relay else {

      throw RelayStateLinkingError.notARelay(device, product: DeviceControlModel.product(of: description))

    }

    return description

  }

  /// Runs a request to a device, and throws ``RelayStateLinkingError/notLinkedToModem(_:)``
  /// when the device rejects the modem because it isn't linked to it.
  private func rejectingUnlinked<Value>(_ device: InsteonAddress, _ request: () async throws -> Value) async throws -> Value {

    do {

      return try await request()

    } catch let ModemError.deviceRejected(_, reason) where reason == .notLinked {

      throw RelayStateLinkingError.notLinkedToModem(device)

    }

  }

  /// Reads operating flags with Get Operating Flags, each request once, however many flags
  /// its reply holds.
  ///
  /// - Throws: ``RelayStateLinkingError/notLinkedToModem(_:)`` when the device rejects the
  ///   modem, ``RelayStateLinkingError/flagUnreadable(_:flag:)`` for a reply that doesn't
  ///   carry a flag, and the modem's errors, such as `ModemError.deviceTimedOut`.
  private func readFlags(_ flags: [OperatingFlag], of target: Device) async throws -> RelayFlags {

    var reading = RelayFlags()
    var replies: [OperatingFlagsRequest: ReceivedMessage] = [:]

    for flag in flags {

      let reply: ReceivedMessage

      if let known = replies[flag.query] {

        reply = known

      } else {

        reply = try await rejectingUnlinked(target.address) { () async throws -> ReceivedMessage in

          try await Self.read(flag, of: target)

        }
        replies[flag.query] = reply

      }

      guard let isSet = flag.isSet(in: reply) else {

        throw RelayStateLinkingError.flagUnreadable(target.address, flag: flag.name.rawValue)

      }

      reading.states[flag.name] = isSet
      reading.bytes[flag.query] = reply.command.command2

    }

    return reading

  }

  /// Sends Get Operating Flags for a flag's request through the device's guarded send path.
  private static func read(_ flag: OperatingFlag, of target: Device) async throws -> ReceivedMessage {

    try await target.request(StandardMessage(to: target.address, command: flag.readCommand), timeout: target.network.requestTimeout, for: .control(.linkingFlags))

  }

  /// Writes a flag through the device's guarded send path, as linking may write it.
  private static func write(_ flag: OperatingFlag, isSet: Bool, of target: Device, writableFlags: Set<SettingName>) async throws {

    let condition = DeviceProfile.Group.Condition(flag: flag.name, isSet: isSet)

    try await target.sendLinkingMessage(.flag(condition), duration: nil, writableFlags: writableFlags, for: .linkingFlags)

  }

  /// Switches the relay with its group type's On or Off through the device's guarded send
  /// path, which records its level in the network's state.
  private static func switchRelay(_ target: Device, to state: RelayState) async throws {

    switch state {
    case .on:
      _ = try await target.turnOn()
    case .off:
      try await target.turnOff()
    }

  }

  /// Links the relay in one link as the modem's responder, without falling back to its SET
  /// button, and records that its databases may have changed when that throws.
  private func link(
    _ device: InsteonAddress,
    group: AllLinkGroupNumber,
    twoWay: TwoWayLinking,
    setButtonTimeout: Duration,
    description: DeviceDescription,
    observer: any LinkingObserver
  ) async throws -> DeviceLinkingResult {

    do {

      return try await linkByAddress(
        device,
        as: .controller,
        group: group,
        twoWay: twoWay,
        setButtonTimeout: setButtonTimeout,
        description: description,
        fallsBackToSETButton: false,
        observer: observer
      )

    } catch {

      // A link may have been made.
      await network.recordLinkChange(of: device, answered: false)

      if error is CancellationError || Self.reportedLink(in: error) != nil {

        throw error

      }

      throw RelayStateLinkingError.remoteLinkingFailed(device, reason: error)

    }

  }

  /// Reads the relay's responder record of the modem for the link's group from its database,
  /// and compares its Data 1 with the state.
  ///
  /// - Returns: The record's Data 1, or `nil` when it wasn't read, and why it doesn't hold the
  ///   state, or `nil` when it does.
  /// - Throws: `CancellationError` if the task is canceled.
  private func checkRecord(of device: InsteonAddress, group: AllLinkGroupNumber, state: RelayState) async throws -> (data1: UInt8?, failure: RelayStateLinkingError?) {

    do {

      let modem: InsteonAddress = try await network.modemInfo().address
      let records: [AllLinkRecordResponse] = try await network.modem.readAllLinkDatabase(of: device, timeout: Modem.defaultExtendedRequestTimeout)

      guard let record = records.map(\.record).first(where: { (record: AllLinkRecord) -> Bool in

        record.flags.contains(.inUse) && !record.flags.contains(.controller) && record.address == modem && record.group == group

      }) else {

        return (nil, .recordNotFound(device, group: group))

      }

      guard record.data1 == state.data1 else {

        return (record.data1, .recordedOtherState(device, group: group, data1: record.data1, requested: state))

      }

      return (record.data1, nil)

    } catch let error as CancellationError {

      throw error

    } catch {

      return (nil, .recordNotRead(device, reason: error))

    }

  }

  /// Puts back what linking changed, to its end even when the task is canceled, and tells the
  /// observer how it went: a momentary relay that was switched goes back to its state before
  /// the link while its flag is still off, then the flag is turned back on and read back,
  /// once more if that fails, and the whole flags byte is compared with the one read first.
  ///
  /// - Parameters:
  ///   - flag: The flag turned off for the link.
  ///   - before: The relay's state before the link, when it was switched, or `nil`.
  ///   - target: The relay.
  ///   - originalFlags: The flags byte the flag is in, as read before the link.
  ///   - writableFlags: The flags linking may write.
  ///   - observer: What a person is told.
  /// - Returns: Whether the relay is momentary afterward, and what didn't go back.
  private func putBack(
    _ flag: OperatingFlag,
    relayTo before: RelayState?,
    of target: Device,
    originalFlags: UInt8?,
    writableFlags: Set<SettingName>,
    observer: any LinkingObserver
  ) async -> Restored {

    let device: InsteonAddress = target.address
    let name: String = flag.name.rawValue

    return await Self.runToEnd { () async -> Restored in

      var failures: [RelayStateLinkingError] = []

      func fail(_ failure: RelayStateLinkingError) async {

        failures.append(failure)
        await observer.linking(.relayState(.restoreFailed(device, failure)))

      }

      if let before {

        await observer.linking(.relayState(.returningRelay(device, before)))

        do {

          try await Self.switchRelay(target, to: before)

        } catch {

          await fail(.relayNotReturned(device, state: before, reason: error))

        }

      }

      await observer.linking(.relayState(.restoringFlag(device, flag: name)))

      var readBack: UInt8?
      var lastFailure: (any Error)?
      var lastWasRead: Bool = false

      // Once more when it fails, since the device may have missed one message.
      for _ in 1...2 where readBack == nil {

        do {

          try await Self.write(flag, isSet: true, of: target, writableFlags: writableFlags)

        } catch {

          lastFailure = error
          lastWasRead = false

          continue

        }

        do {

          let byte: UInt8 = try await Self.read(flag, of: target).command.command2

          if byte & flag.bit != 0 {

            readBack = byte

          } else {

            lastFailure = RelayStateLinkingError.flagNotChanged(device, flag: name, isSet: true)
            lastWasRead = false

          }

        } catch {

          lastFailure = error
          lastWasRead = true

        }

      }

      guard let readBack else {

        let reason: any Error = lastFailure ?? RelayStateLinkingError.flagNotChanged(device, flag: name, isSet: true)

        await fail(lastWasRead ? .flagRestoreUnconfirmed(device, flag: name, reason: reason) : .flagNotRestored(device, flag: name, reason: reason))

        return Restored(isMomentary: false, failures: failures)

      }

      await observer.linking(.relayState(.flagRestored(device, flag: name)))

      if let originalFlags, readBack != originalFlags {

        await fail(.otherFlagsChanged(device, before: originalFlags, after: readBack))

      }

      return Restored(isMomentary: true, failures: failures)

    }

  }

}
