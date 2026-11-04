import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

// Linking a relay with a chosen state.
extension DeviceLinkingCoordinator {

  /// Links a relay by its address so it records a chosen state: a group On from the modem
  /// then sets the relay to it, and a group Off to the opposite.
  ///
  /// The modem is the controller, and the device's main group must be a relay whose type the
  /// catalog says how it holds a state, in its `stateHolding`; a relay the catalog says
  /// nothing about is refused before anything but reads is sent. A device the registry
  /// doesn't know is asked for its identity with ID Request first. Then, in order:
  ///
  /// 1. The flags the catalog names in how the relay holds a state are read with Get
  ///    Operating Flags, and its status with the command its group type names. A device that
  ///    rejects the modem, as an i2CS device does until it holds a link to it, is refused
  ///    here.
  /// 2. When every flag of one of the catalog's sets that make every On and Off pulse the
  ///    relay is on, the state is ignored: the relay is linked without being switched, no
  ///    flag is written, and its record isn't held to the state. Otherwise, when the relay
  ///    isn't in the state, or doesn't hold a state and the state isn't its rest state, it
  ///    must be sent a command. A relay with a flag on that keeps it from holding a state
  ///    would return to its rest state before it links, so, unless the state is its rest
  ///    state, each such flag is turned off first and read back, but only when the catalog's
  ///    linking changes allow it, and when the messages that turn the flag off, set it back
  ///    and return the relay would be sent; otherwise the link is refused. A relay switched to
  ///    its rest state stays there by itself, so no flag is written for it. A relay already in
  ///    the state is sent nothing, and no flag is written. ``DeviceLinkingCoordinator/planRelayLink(_:recording:observer:)``
  ///    reads the same and says what will be switched, for a front end to ask first.
  /// 3. The relay is sent its group type's On or Off through the device's guarded send path,
  ///    and its status is read again; a relay that doesn't show the state isn't linked.
  /// 4. The device is linked in one link, in the modem's `group`, not by the catalog's legs.
  ///    A device that doesn't link without its SET button isn't linked with it, since that
  ///    records whatever state the relay is in by the time a person presses it.
  /// 5. A relay whose flags were turned off is switched to its rest state while its flags are
  ///    still off, once more if that fails; then each flag is turned back on and read back,
  ///    once more if that fails, and each whole flags byte compared with the one read first.
  /// 6. The relay's responder record is read back, through the network's cache, and its
  ///    Data 1 compared with the state the link fixed.
  ///
  /// Step 5 runs however linking ends, after a failure and when the task is canceled. A relay
  /// that holds a state keeps the state it recorded once the link is made; when linking
  /// fails or is canceled after it was switched, it's switched back to its state before, but
  /// only while its status still reads the state it was switched to, or can't be read, and
  /// not when its status already disagreed with it. Every command that sets the relay or
  /// switches it back is checked before anything changes. The
  /// observer gets ``LinkingEvent/relayState(_:)`` for each step, and the result's
  /// ``DeviceLinkingResult/relayState`` says what a group On and a group Off do, and what
  /// didn't go as asked once the link was made, which doesn't throw.
  ///
  /// ```swift
  /// let result = try await network.linking.linkRelay(relay, recording: .off, group: 2, observer: prompter)
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
  ///   link without its SET button, ``DeviceControlError`` or `FieldError` when a message it
  ///   needs would be refused, `LinkMismatch` or `LinkingError.unexpectedLink(_:)` when the modem reports
  ///   another link, the modem's errors, such as `ModemError.deviceTimedOut` when the device
  ///   doesn't answer, and `CancellationError` if the task is canceled.
  public func linkRelay(
    _ device: InsteonAddress,
    recording state: RelayState,
    group: AllLinkGroupNumber = DeviceLinkingCoordinator.defaultModemGroup,
    twoWay: TwoWayLinking = .whenDeviceControls,
    setButtonTimeout: Duration = Linker.defaultManualLinkingTimeout,
    observer: any LinkingObserver
  ) async throws -> DeviceLinkingResult {

    try await linkRelay(device, recording: state, approved: nil, group: group, twoWay: twoWay, setButtonTimeout: setButtonTimeout, observer: observer)

  }

  /// Links a relay as a plan from
  /// ``DeviceLinkingCoordinator/planRelayLink(_:recording:observer:)`` says, once a person
  /// approved it, as
  /// ``DeviceLinkingCoordinator/linkRelay(_:recording:group:twoWay:setButtonTimeout:observer:)``
  /// does.
  ///
  /// The relay is read again inside the link. When its plan differs from the approved one,
  /// such as when someone switched the relay since, nothing is sent but those reads, and
  /// ``RelayStateLinkingError/planChanged(old:new:)`` is thrown, so the relay is never
  /// switched other than the plan showed. The plan is compared whole, readings and all, so a
  /// changed reading is refused even when the steps it leads to would be the same: a person
  /// approved what they were shown, and is shown it again.
  ///
  /// - Parameters:
  ///   - plan: The plan a person approved.
  ///   - group: The modem's group. Defaults to ``DeviceLinkingCoordinator/defaultModemGroup``.
  ///   - twoWay: Whether to link the device back. Defaults to
  ///     ``TwoWayLinking/whenDeviceControls``.
  ///   - setButtonTimeout: How long the modem waits in linking mode for a link back. Defaults
  ///     to ``defaultSETButtonTimeout``.
  ///   - observer: What a person is told.
  /// - Returns: The links made, the device, and the relay's ``RelayStateLink``.
  /// - Throws: ``RelayStateLinkingError/planChanged(old:new:)`` when the relay changed since
  ///   the plan, and the errors of
  ///   ``DeviceLinkingCoordinator/linkRelay(_:recording:group:twoWay:setButtonTimeout:observer:)``.
  public func linkRelay(
    _ plan: RelayLinkPlan,
    group: AllLinkGroupNumber = DeviceLinkingCoordinator.defaultModemGroup,
    twoWay: TwoWayLinking = .whenDeviceControls,
    setButtonTimeout: Duration = Linker.defaultManualLinkingTimeout,
    observer: any LinkingObserver
  ) async throws -> DeviceLinkingResult {

    try await linkRelay(plan.device, recording: plan.state, approved: plan, group: group, twoWay: twoWay, setButtonTimeout: setButtonTimeout, observer: observer)

  }

  /// Links a relay with a state, after checking its plan against an approved one, if any.
  private func linkRelay(
    _ device: InsteonAddress,
    recording state: RelayState,
    approved: RelayLinkPlan?,
    group: AllLinkGroupNumber,
    twoWay: TwoWayLinking,
    setButtonTimeout: Duration,
    observer: any LinkingObserver
  ) async throws -> DeviceLinkingResult {

    // The device's databases are recorded as changed only once a link may have been made, so
    // a refusal leaves the network's copies as they are.
    try await inTurn(changing: nil) { () async throws -> DeviceLinkingResult in

      let prepared: Preparation = try await prepare(device, recording: state, observer: observer)
      let plan: RelayLinkPlan = prepared.plan

      if let approved, approved != plan {

        throw RelayStateLinkingError.planChanged(old: approved, new: plan)

      }

      let target: Device = prepared.target
      let writableFlags: Set<SettingName> = prepared.writableFlags
      let before: RelayState = plan.before

      // What to put back however linking ends: the flags turned off, and whether the relay
      // was switched.
      var cleared: [(flag: RelayFlag, operating: OperatingFlag)] = []
      var switched: Bool = false
      let putBack = { (flags: [(flag: RelayFlag, operating: OperatingFlag)], wasSwitched: Bool) async -> Restored in

        await self.putBack(flags, returningTo: plan.returnsToRestAfterLinking && wasSwitched ? plan.holding.restState : nil, of: target, originalFlags: prepared.flags.bytes, writableFlags: writableFlags, observer: observer)

      }

      do {

        for (flag, operating) in prepared.clearedFlags {

          await observer.linking(.relayState(.clearingFlag(device, flag: flag)))

          do {

            try await Self.write(operating, isSet: false, of: target, writableFlags: writableFlags)

          } catch {

            // A refusal comes before anything is sent; any other error may follow the
            // message reaching the device.
            if !(error is DeviceControlError || error is FieldError) {

              cleared.append((flag, operating))

            }

            throw error

          }

          cleared.append((flag, operating))

          guard try await Self.read(operating, of: target).command.command2 & operating.bit == 0 else {

            throw RelayStateLinkingError.flagNotChanged(device, flag: flag, isSet: false)

          }

        }

        if plan.switchesRelay {

          await observer.linking(.relayState(.settingRelay(device, state)))

          // Set first: the relay may have switched though its acknowledgment was lost.
          switched = true

          try await Self.switchRelay(target, to: state)

          guard try await target.status().isOn == (state == .on) else {

            throw RelayStateLinkingError.relayNotConfirmed(device, requested: state)

          }

          await observer.linking(.relayState(.relayConfirmed(device, state)))

        } else if plan.ignoresState {

          await observer.linking(.relayState(.linkedWithoutSwitching(device, flags: plan.holding.pulsingFlags)))

        } else {

          await observer.linking(.relayState(.relayAlreadySet(device, state)))

        }

        var result: DeviceLinkingResult = try await linkWithoutSETButton(device, group: group, twoWay: twoWay, setButtonTimeout: setButtonTimeout, description: prepared.description, observer: observer)
        // The link fixed the record's Data 1, so from here a relay that holds a state keeps
        // it, and one whose flags were turned off is put back at once, before its record is
        // read.
        let wasSwitched: Bool = switched
        var holding: RelayStateHolding = plan.holding
        var restoreFailures: [RelayStateLinkingError] = []

        switched = false

        if !cleared.isEmpty {

          let flags = cleared

          cleared = []

          let restored: Restored = await putBack(flags, wasSwitched)

          // A flag turned off is on afterward only when it read back on.
          holding.flagsOn.removeAll { (flag: RelayFlag) -> Bool in

            flags.contains { (cleared: (flag: RelayFlag, operating: OperatingFlag)) -> Bool in cleared.flag == flag } && !restored.flagsOn.contains(flag)

          }
          restoreFailures = restored.failures

        }

        let linkedGroup: AllLinkGroupNumber = result.links.first?.group ?? group
        // Only a relay that ignores the state isn't held to it; every other result claims it.
        let recorded: (data1: UInt8?, failure: RelayStateLinkingError?) = try await checkRecord(of: device, group: linkedGroup, state: plan.ignoresState ? nil : state)
        let link = RelayStateLink(
          device: device,
          state: state,
          group: linkedGroup,
          recordedData1: recorded.data1,
          recordFailure: recorded.failure,
          clearedFlags: plan.clearedFlags,
          holding: holding,
          restoreFailures: restoreFailures
        )

        await observer.linking(.relayState(.recorded(link)))
        result.relayState = link

        return result

      } catch {

        // What didn't go back is reported, and the error that stopped linking thrown.
        if !cleared.isEmpty {

          _ = await putBack(cleared, switched)

        } else if switched, Self.isUnconfirmedRelay(error) {

          // Its status already disagreed with the state, so it isn't switched again.
          await observer.linking(.relayState(.relayLeft(device, reads: state.opposite)))

        } else if switched {

          // A relay that holds a state goes back to its state before, since nothing
          // recorded the one it was switched to.
          _ = await returnRelay(target, from: state, to: before, observer: observer)

        }

        throw error

      }

    }

  }

  /// Reads a relay's flags and status and plans what linking it with a state switches and
  /// puts back, as
  /// ``DeviceLinkingCoordinator/linkRelay(_:recording:group:twoWay:setButtonTimeout:observer:)``
  /// would, and sends nothing else: no command, no flag write, no link. A front end shows the
  /// plan, and asks before it links, since the relay, and whatever it controls, is switched.
  ///
  /// The relay may change between the plan and the link, so the link plans again.
  ///
  /// - Parameters:
  ///   - device: The relay.
  ///   - state: The state it's to record.
  ///   - observer: What a person is told while a device the registry doesn't know is asked
  ///     for its identity.
  /// - Returns: The plan.
  /// - Throws: The refusals of
  ///   ``DeviceLinkingCoordinator/linkRelay(_:recording:group:twoWay:setButtonTimeout:observer:)``
  ///   that come before anything changes, such as
  ///   ``RelayStateLinkingError/stateHoldingNotDescribed(_:product:)`` for a relay the
  ///   catalog doesn't say how it holds a state; the modem's errors; and `CancellationError`
  ///   if the task is canceled.
  public func planRelayLink(_ device: InsteonAddress, recording state: RelayState, observer: any LinkingObserver) async throws -> RelayLinkPlan {

    try await inTurn(changing: nil) { () async throws -> RelayLinkPlan in

      try await prepare(device, recording: state, observer: observer).plan

    }

  }

  /// What linking a relay with a state starts from, once every check that comes before
  /// anything changes has passed.
  private struct Preparation {

    var plan: RelayLinkPlan

    var description: DeviceDescription

    var target: Device

    /// The flags the plan turns off, each with its operating flag, in order.
    var clearedFlags: [(flag: RelayFlag, operating: OperatingFlag)]

    var flags: RelayFlags

    var writableFlags: Set<SettingName>

  }

  /// Reads the relay's flags and status, plans the link, and checks, without sending them,
  /// every message the plan sends or may send to put things back.
  private func prepare(_ device: InsteonAddress, recording state: RelayState, observer: any LinkingObserver) async throws -> Preparation {

    let description: DeviceDescription = try await relayDescription(of: device, observer: observer)
    let target: Device = network.device(device)
    let read: StateHoldingReading = try await readStateHolding(description, of: target)
    let before: RelayState = try await rejectingUnlinked(device) { () async throws -> Bool in try await target.status().isOn } ? .on : .off
    let plan = RelayLinkPlan(device: device, state: state, before: before, holding: read.holding)
    // A relay link writes only the flags the catalog lets a linking flow change around it.
    let writableFlags = Set<SettingName>(description.commandSet?.linkingChanges.map(\.flag) ?? [])

    if plan.switchesRelay {

      // A command that would be refused is found before anything changes: the one that sets
      // the relay, and, for a relay that holds a state, the one that switches it back when
      // linking fails.
      try await target.refuseUnlessSwitchable(on: state == .on)

      if plan.switchesBackOnFailure {

        try await target.refuseUnlessSwitchable(on: before == .on)

      }

    }

    var clearedFlags: [(flag: RelayFlag, operating: OperatingFlag)] = []

    for flag in plan.clearedFlags {

      guard let operating = read.operatingFlags[flag.name], writableFlags.contains(operating.name) else {

        throw RelayStateLinkingError.flagNotChangeable(device, flag: flag)

      }

      clearedFlags.append((flag, operating))

      // A flag that couldn't be turned off or set back is never cleared: both messages are
      // checked first, and nothing is sent.
      for isSet in [false, true] {

        do {

          try await target.refuseUnlessSendable(.flag(DeviceProfile.Group.Condition(flag: operating.name, isSet: isSet)), writableFlags: writableFlags, for: .linkingFlags)

        } catch let error as DeviceControlError {

          throw RelayStateLinkingError.flagNotWritable(device, flag: flag, reason: error)

        }

      }

    }

    if plan.returnsToRestAfterLinking {

      // The relay is returned to its rest state after the link, so that command is checked
      // too.
      try await target.refuseUnlessSwitchable(on: plan.holding.restState == .on)

    }

    return Preparation(plan: plan, description: description, target: target, clearedFlags: clearedFlags, flags: read.flags, writableFlags: writableFlags)

  }

  /// How a relay holds a state, as the catalog describes its main group's type and its flags
  /// read, with the operating flags the catalog names, by name, and what each request read.
  struct StateHoldingReading {

    var holding: RelayStateHolding

    var operatingFlags: [String: OperatingFlag]

    var flags: RelayFlags

  }

  /// Reads the flags the catalog names in how a relay holds a state with Get Operating Flags,
  /// each request once.
  ///
  /// A relay that names no flag that releases it always holds its state: nothing is read, and
  /// its pulsing sets don't apply.
  ///
  /// - Throws: ``RelayStateLinkingError/stateHoldingNotDescribed(_:product:)`` when the catalog
  ///   doesn't say how the relay holds a state,
  ///   ``RelayStateLinkingError/stateHoldingFlagUnknown(_:flag:)`` when it names a flag its
  ///   command set doesn't give, ``RelayStateLinkingError/restStateUnknown(_:action:)`` when
  ///   it names a rest state other than the group type's On or Off action, and the errors of
  ///   ``readFlags(_:of:)``.
  func readStateHolding(_ description: DeviceDescription, of target: Device) async throws -> StateHoldingReading {

    let device: InsteonAddress = target.address
    guard let described = description.mainGroupType?.stateHolding else {

      throw RelayStateLinkingError.stateHoldingNotDescribed(device, product: DeviceControlModel.product(of: description))

    }

    let restState: RelayState

    // The rest state names one of the group type's actions: the relay's On or Off. Whether
    // the relay can be switched to it is checked before anything changes.
    switch described.restState {
    case DeviceControlModel.onAction:
      restState = .on
    case DeviceControlModel.offAction:
      restState = .off
    default:
      throw RelayStateLinkingError.restStateUnknown(device, action: described.restState.rawValue)
    }

    var names: [SettingName] = []
    let pulsing: [SettingName] = described.pulsesOnEveryCommandWhen.flatMap { (set: [SettingName]) -> [SettingName] in set }

    for name in described.releasedBy + pulsing where !names.contains(name) {

      names.append(name)

    }

    let commands: CommandSet? = description.commandSet
    var operatingFlags: [OperatingFlag] = []

    // Every flag the catalog names is checked, though a relay nothing releases always holds
    // its state, so its pulsing sets don't apply and only its releasing flags would be read.
    for name in names {

      guard let flag = commands?.operatingFlag(named: name) else {

        throw RelayStateLinkingError.stateHoldingFlagUnknown(device, flag: name.rawValue)

      }

      if !described.releasedBy.isEmpty {

        operatingFlags.append(flag)

      }

    }

    let reading: RelayFlags = try await readFlags(operatingFlags, of: target)
    let flagsOn: [RelayFlag] = operatingFlags.filter { (flag: OperatingFlag) -> Bool in reading.states[flag.name] == true }.map(Self.relayFlag)
    let holding = RelayStateHolding(
      releasedBy: described.releasedBy.map(\.rawValue),
      restState: restState,
      pulsesOnEveryCommandWhen: described.pulsesOnEveryCommandWhen.map { (set: [SettingName]) -> [String] in set.map(\.rawValue) },
      flagsOn: flagsOn
    )

    return StateHoldingReading(
      holding: holding,
      operatingFlags: Dictionary(operatingFlags.map { (flag: OperatingFlag) -> (String, OperatingFlag) in (flag.name.rawValue, flag) }) { (first: OperatingFlag, _: OperatingFlag) -> OperatingFlag in first },
      flags: reading
    )

  }

  /// An operating flag as a person reads it: its name, and the catalog's label or its name.
  static func relayFlag(_ flag: OperatingFlag) -> RelayFlag {

    RelayFlag(name: flag.name.rawValue, label: flag.label ?? flag.name.rawValue)

  }

  /// The operating flags a relay reported, read once per Get Operating Flags request.
  struct RelayFlags {

    /// Whether each flag is set, by its name.
    var states: [SettingName: Bool] = [:]

    /// The whole byte each request reported.
    var bytes: [OperatingFlagsRequest: UInt8] = [:]

  }

  /// How putting back what linking changed went.
  private struct Restored: Sendable {

    /// The flags turned off for the link that read back on.
    var flagsOn: [RelayFlag]

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
  func readFlags(_ flags: [OperatingFlag], of target: Device) async throws -> RelayFlags {

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

        throw RelayStateLinkingError.flagUnreadable(target.address, flag: Self.relayFlag(flag))

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
  private func linkWithoutSETButton(
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
  /// and compares its Data 1 with the state, or doesn't when `state` is `nil`.
  ///
  /// - Returns: The record's Data 1, or `nil` when it wasn't read, and why it doesn't hold the
  ///   state, or `nil` when it does.
  /// - Throws: `CancellationError` if the task is canceled.
  private func checkRecord(of device: InsteonAddress, group: AllLinkGroupNumber, state: RelayState?) async throws -> (data1: UInt8?, failure: RelayStateLinkingError?) {

    do {

      let modem: InsteonAddress = try await network.modemInfo().address
      // Through the network's cache, so the copy read serves what reads the database next.
      let records: [AllLinkRecordResponse] = try await network.databaseCopy(of: device).records

      guard let record = records.map(\.record).first(where: { (record: AllLinkRecord) -> Bool in

        record.flags.contains(.inUse) && !record.flags.contains(.controller) && record.address == modem && record.group == group

      }) else {

        return (nil, .recordNotFound(device, group: group))

      }

      guard let state, record.data1 != state.data1 else {

        return (record.data1, nil)

      }

      return (record.data1, .recordedOtherState(device, group: group, data1: record.data1, requested: state))

    } catch let error as CancellationError {

      throw error

    } catch {

      return (nil, .recordNotRead(device, reason: error))

    }

  }

  /// Puts back what linking changed on a relay whose flags were turned off, to its end even
  /// when the task is canceled, and tells the observer how it went: a relay switched out of
  /// its rest state is returned to it while its flags are still off, then each flag is turned
  /// back on and read back, each once more if it fails, and each whole flags byte is compared
  /// with the one read first.
  ///
  /// - Parameters:
  ///   - flags: The flags turned off for the link, in the order they were.
  ///   - restState: The state to return the relay to first, or `nil` to leave it.
  ///   - target: The relay.
  ///   - originalFlags: Each flags byte, as read before the link.
  ///   - writableFlags: The flags linking may write.
  ///   - observer: What a person is told.
  /// - Returns: The flags that read back on, and what didn't go back.
  private func putBack(
    _ flags: [(flag: RelayFlag, operating: OperatingFlag)],
    returningTo restState: RelayState?,
    of target: Device,
    originalFlags: [OperatingFlagsRequest: UInt8],
    writableFlags: Set<SettingName>,
    observer: any LinkingObserver
  ) async -> Restored {

    let device: InsteonAddress = target.address

    return await Self.runToEnd { () async -> Restored in

      var failures: [RelayStateLinkingError] = []
      var flagsOn: [RelayFlag] = []
      // The last byte each request read back, and the requests a flag wasn't confirmed in.
      var readBacks: [OperatingFlagsRequest: UInt8] = [:]
      var unconfirmed: Set<OperatingFlagsRequest> = []

      if let restState, let failure = await Self.switchBack(target, to: restState, observer: observer) {

        failures.append(failure)

      }

      for (flag, operating) in flags {

        await observer.linking(.relayState(.restoringFlag(device, flag: flag)))

        var readBack: UInt8?
        var lastFailure: (any Error)?
        // Whether the device acknowledged a write, so the flag may be on though it wasn't read.
        var wasAcknowledged: Bool = false

        // Once more when it fails, since the device may have missed one message.
        for _ in 1...2 where readBack == nil {

          do {

            try await Self.write(operating, isSet: true, of: target, writableFlags: writableFlags)

            wasAcknowledged = true

            let byte: UInt8 = try await Self.read(operating, of: target).command.command2

            if byte & operating.bit != 0 {

              readBack = byte

            } else {

              wasAcknowledged = false
              lastFailure = RelayStateLinkingError.flagNotChanged(device, flag: flag, isSet: true)

            }

          } catch {

            lastFailure = error

          }

        }

        guard let readBack else {

          let reason: any Error = lastFailure ?? RelayStateLinkingError.flagNotChanged(device, flag: flag, isSet: true)
          let failure: RelayStateLinkingError = wasAcknowledged
            ? .flagRestoreUnconfirmed(device, flag: flag, reason: reason)
            : .flagNotRestored(device, flag: flag, reason: reason)

          failures.append(failure)
          unconfirmed.insert(operating.query)
          await observer.linking(.relayState(.restoreFailed(device, failure)))

          continue

        }

        await observer.linking(.relayState(.flagRestored(device, flag: flag)))
        flagsOn.append(flag)
        readBacks[operating.query] = readBack

      }

      // Each byte whose flags all read back on is compared whole, in the order its first flag
      // was turned off.
      var compared: Set<OperatingFlagsRequest> = []

      for (_, operating) in flags where !unconfirmed.contains(operating.query) && compared.insert(operating.query).inserted {

        if let original = originalFlags[operating.query], let readBack = readBacks[operating.query], readBack != original {

          let failure = RelayStateLinkingError.otherFlagsChanged(device, before: original, after: readBack)

          failures.append(failure)
          await observer.linking(.relayState(.restoreFailed(device, failure)))

        }

      }

      return Restored(flagsOn: flagsOn, failures: failures)

    }

  }

  /// Whether an error is a relay's status disagreeing with the state it was switched to.
  private static func isUnconfirmedRelay(_ error: any Error) -> Bool {

    if case .relayNotConfirmed? = error as? RelayStateLinkingError {

      return true

    }

    return false

  }

  /// Switches a relay that holds a state back to its state before linking failed, to its
  /// end even when the task is canceled: only when its status still reads the state it was
  /// switched to, since someone may have switched it since, and also when the status can't
  /// be read, which is reported.
  ///
  /// - Parameters:
  ///   - target: The relay.
  ///   - switched: The state it was switched to.
  ///   - before: Its state before.
  ///   - observer: What a person is told.
  /// - Returns: Why it wasn't switched back, or isn't known to have been, or `nil`.
  private func returnRelay(_ target: Device, from switched: RelayState, to before: RelayState, observer: any LinkingObserver) async -> RelayStateLinkingError? {

    await Self.runToEnd { () async -> RelayStateLinkingError? in

      let unread: (any Error)?

      do {

        let isOn: Bool = try await target.status().isOn

        guard isOn == (switched == .on) else {

          await observer.linking(.relayState(.relayLeft(target.address, reads: isOn ? .on : .off)))

          return nil

        }

        unread = nil

      } catch {

        unread = error

      }

      if let failure = await Self.switchBack(target, to: before, observer: observer) {

        return failure

      }

      guard let unread else {

        return nil

      }

      let failure = RelayStateLinkingError.relayReturnUnconfirmed(target.address, state: before, reason: unread)

      await observer.linking(.relayState(.restoreFailed(target.address, failure)))

      return failure

    }

  }

  /// Switches a relay back to a state, once more if that fails, and tells the observer.
  ///
  /// - Returns: Why it wasn't switched back, or `nil` when it was.
  private static func switchBack(_ target: Device, to state: RelayState, observer: any LinkingObserver) async -> RelayStateLinkingError? {

    await observer.linking(.relayState(.returningRelay(target.address, state)))

    var lastFailure: (any Error)?

    for _ in 1...2 {

      do {

        try await switchRelay(target, to: state)

        return nil

      } catch {

        lastFailure = error

      }

    }

    let failure = RelayStateLinkingError.relayNotReturned(target.address, state: state, reason: lastFailure ?? RelayStateLinkingError.relayNotConfirmed(target.address, requested: state))

    await observer.linking(.relayState(.restoreFailed(target.address, failure)))

    return failure

  }

}
