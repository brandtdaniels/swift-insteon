import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

extension DeviceLinkingCoordinator {

  /// Links a device's legs of the catalog's linking from a Hub, in the catalog's order, in the
  /// caller's turn.
  ///
  /// Before the first leg, when it has the modem as controller and the device doesn't go
  /// first, a light or switched load is turned fully on with Light On, as for any link with
  /// the modem as controller. Then, for each leg:
  ///
  /// 1. The observer gets ``LinkingEvent/allGroupsWhen(_:condition:)`` when the catalog says
  ///    the leg covers every group the device controls under an operating flag state, then
  ///    ``LinkingEvent/hubLinkingLegStarted(_:)``.
  /// 2. For the first leg of a device that goes first, the observer is asked to have the
  ///    device put in linking mode with the catalog's steps, and the modem joins it in the
  ///    leg's role and group.
  /// 3. Otherwise the modem starts ALL-Linking first in the leg's role and group, and the
  ///    device joins: with Enter Linking Mode for the leg's device group, standard or extended
  ///    by its engine, unless the catalog says Enter Linking Mode doesn't work for it, when
  ///    the observer is told to have its SET button pressed, with the catalog's steps.
  /// 4. The coordinator waits for ALL-Linking Completed (`0x53`), records the link, and the
  ///    observer gets ``LinkingEvent/linked(_:)`` and
  ///    ``LinkingEvent/hubLinkingLegCompleted(_:link:)`` before the next leg starts.
  ///
  /// When Enter Linking Mode fails for the first leg, the device is linked with its SET button
  /// instead, as for a device without legs, and ``LinkingFallback/setButtonLeg(_:reason:)``
  /// says whether the catalog expected Enter Linking Mode to work. A later leg falls back the
  /// same way when the device can't take Enter Linking Mode at all, and once a leg is linked
  /// with the SET button, every leg after it is too, each with its own prompt. A later leg that
  /// fails otherwise, such as when its link times out, is reported with
  /// ``LinkingEvent/hubLinkingLegFailed(_:reason:notRun:)``, the same whatever the catalog
  /// says, and stops the legs after it; the links made stay made, and the result's
  /// ``DeviceLinkingResult/legs`` say which leg failed and which weren't run. When a later leg
  /// throws, as when it's canceled or another device links, the observer gets
  /// ``LinkingEvent/hubLinkingStopped(_:reason:)`` with the legs linked so far first.
  ///
  /// When the catalog says how to keep a battery-powered device awake, the coordinator sends
  /// that message through the device's guarded send path, as ``KeepAwakeEvent`` reports:
  /// before the first leg, once the observer says a person has woken the device, or right
  /// after the first leg's link, as the catalog's timing says. A timing this package doesn't
  /// know isn't sent. Once the legs are done, or stopped by an error or cancellation, the
  /// catalog's message that lets the device sleep again is sent, when it gives one and the
  /// first message may have reached the device. No operating flag is written but the ones
  /// these messages name, and the command set's ``CommandSet/linkingChanges``.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - legs: The catalog's legs, in order.
  ///   - description: What the catalog says about the device.
  ///   - setButtonTimeout: How long the modem waits for a device linked with its SET button.
  ///   - observer: What a person is told and asked.
  /// - Returns: Each leg's link, the device, and what became of each leg.
  /// - Throws: The first leg's errors, `LinkMismatch` or `LinkingError.unexpectedLink(_:)`
  ///   when the modem reports another link, the observer's errors, and `CancellationError` if
  ///   the task is canceled.
  func linkByLegs(
    _ device: InsteonAddress,
    legs: [HubLinkingLeg],
    description: DeviceDescription?,
    setButtonTimeout: Duration,
    observer: any LinkingObserver
  ) async throws -> DeviceLinkingResult {

    let keepAwake: DeviceLifecycle.HubLinking.KeepAwake? = description?.hubLinking?.keepAwake
    let writableFlags: Set<SettingName> = Self.writableLinkingFlags(of: description)
    var isKeptAwake: Bool = false

    do {

      let result: DeviceLinkingResult = try await linkEachLeg(
        device,
        legs: legs,
        description: description,
        setButtonTimeout: setButtonTimeout,
        writableFlags: writableFlags,
        observer: observer,
        isKeptAwake: &isKeptAwake
      )

      if isKeptAwake {

        await releaseKeepAwake(keepAwake, of: device, writableFlags: writableFlags, observer: observer)

      }

      return result

    } catch {

      if isKeptAwake {

        await releaseKeepAwake(keepAwake, of: device, writableFlags: writableFlags, observer: observer)

      }

      throw error

    }

  }

  /// Links each leg, keeping the device awake as the catalog says, and sets `isKeptAwake` once
  /// the message that keeps it awake may have reached it.
  private func linkEachLeg(
    _ device: InsteonAddress,
    legs: [HubLinkingLeg],
    description: DeviceDescription?,
    setButtonTimeout: Duration,
    writableFlags: Set<SettingName>,
    observer: any LinkingObserver,
    isKeptAwake: inout Bool
  ) async throws -> DeviceLinkingResult {

    let hubLinking: DeviceLifecycle.HubLinking? = description?.hubLinking
    let isDeviceFirst: Bool = hubLinking?.isDeviceFirst ?? false
    let keepAwake: DeviceLifecycle.HubLinking.KeepAwake? = hubLinking?.keepAwake

    if let keepAwake, keepAwake.timing == .beforeLinking {

      let steps: [DeviceLifecycle.Step] = Self.deviceSteps(of: description?.profile?.lifecycle?.waking)

      try await observer.waitUntilDeviceIsAwake(WakePrompt(device: device, deviceDescription: description, steps: steps))

      // Set first, so a cancellation while it's sent still lets the device sleep again.
      isKeptAwake = true
      isKeptAwake = try await sendKeepAwake(keepAwake, to: device, writableFlags: writableFlags, observer: observer)

    }

    if let first = legs.first, first.modemRole == .controller, !isDeviceFirst {

      try await turnOnBeforeLinking(device, description: description, linker: makeLinker(), observer: observer)

    }

    var outcomes: [HubLinkingLegOutcome] = []
    var links: [AllLinkingCompleted] = []
    var registered: RegisteredDevice?
    // Once Enter Linking Mode doesn't work for one leg, it won't for the rest either.
    var usesSETButton: Bool = false

    for leg in legs {

      if let condition = leg.allGroupsWhen {

        await observer.linking(.allGroupsWhen(leg, condition: condition))

      }

      await observer.linking(.hubLinkingLegStarted(leg))

      let made: (link: AllLinkingCompleted, join: HubLinkingJoin)

      do {

        made = try await link(
          leg,
          goesFirst: leg.isFirst && isDeviceFirst,
          usesSETButton: usesSETButton,
          description: description,
          setButtonTimeout: setButtonTimeout,
          observer: observer
        )

      } catch {

        let notRun: [HubLinkingLeg] = Array(legs.dropFirst(leg.index + 1))
        let stopped: [HubLinkingLegOutcome] = outcomes
          + [HubLinkingLegOutcome(leg: leg, status: .failed(error))]
          + notRun.map { (skipped: HubLinkingLeg) -> HubLinkingLegOutcome in HubLinkingLegOutcome(leg: skipped, status: .notRun) }

        // A canceled link, a link the modem reported for another device or of another kind,
        // and a first leg that made no link at all are the caller's to handle. Legs already
        // linked are reported first, so they aren't lost with the error.
        if error is CancellationError || leg.isFirst || Self.reportedLink(in: error) != nil {

          if !leg.isFirst {

            await observer.linking(.hubLinkingStopped(
              DeviceLinkingResult(links: links, device: registered, linkBackFailure: nil, legs: stopped),
              reason: error
            ))

          }

          // The turn records the change on the way out.
          throw error

        }

        await observer.linking(.hubLinkingLegFailed(leg, reason: error, notRun: notRun))
        await network.recordLinkChange(of: device, answered: true)

        outcomes = stopped

        break

      }

      if made.join == .setButton {

        usesSETButton = true

      }

      await network.recordLinkChange(of: device, answered: true)

      // Right after the first link, while the device is still awake.
      if leg.isFirst, let keepAwake, keepAwake.timing == .afterLinked {

        isKeptAwake = true
        isKeptAwake = try await sendKeepAwake(keepAwake, to: device, writableFlags: writableFlags, observer: observer)

      }

      if leg.isFirst {

        do {

          registered = try await learnIdentity(from: made.link, observer: observer)

        } catch {

          // Something may have read the device's database again while it was identified, so
          // the link is recorded again before the error goes on.
          await network.recordLinkChange(of: device, answered: true)

          throw error

        }

      }

      links.append(made.link)
      outcomes.append(HubLinkingLegOutcome(leg: leg, status: .linked(made.link, by: made.join)))

      await observer.linking(.linked(LinkedDevice(link: made.link, device: registered, leg: leg.isFirst ? .first : .hubLinking(leg.index))))
      await observer.linking(.hubLinkingLegCompleted(leg, link: made.link))

    }

    return DeviceLinkingResult(links: links, device: registered, linkBackFailure: nil, legs: outcomes)

  }

  /// Makes one leg's link, and says how the device joined it.
  ///
  /// - Parameters:
  ///   - leg: The leg.
  ///   - goesFirst: Whether a person puts the device in linking mode before the modem starts.
  ///   - usesSETButton: Whether an earlier leg showed Enter Linking Mode doesn't work for the
  ///     device, so the leg is linked with its SET button.
  ///   - description: What the catalog says about the device.
  ///   - setButtonTimeout: How long the modem waits for a device linked with its SET button.
  ///   - observer: What a person is told and asked.
  /// - Returns: The link the modem reported, and how the device joined.
  private func link(
    _ leg: HubLinkingLeg,
    goesFirst: Bool,
    usesSETButton: Bool,
    description: DeviceDescription?,
    setButtonTimeout: Duration,
    observer: any LinkingObserver
  ) async throws -> (link: AllLinkingCompleted, join: HubLinkingJoin) {

    let device: InsteonAddress = leg.device
    let linker: Linker = makeLinker()
    let steps: [DeviceLifecycle.Step] = Self.deviceSteps(of: description?.profile?.lifecycle?.linking)

    if goesFirst {

      try await observer.waitUntilDeviceIsReady(DeviceFirstPrompt(direction: .linking, device: device, deviceDescription: description, steps: steps))
      await observer.linking(.hubLinkingLegJoined(leg, by: .deviceFirst))
      await observer.linking(.modemJoining(timeout: setButtonTimeout))

      let link: AllLinkingCompleted = try await linker.linkManually(
        as: Self.manualRole(leg.modemRole),
        group: leg.modemGroup,
        device: device,
        timeout: setButtonTimeout
      )

      return (link, .deviceFirst)

    }

    if usesSETButton || leg.remoteEnterLinkingMode == .no {

      let link: AllLinkingCompleted = try await linkBySETButton(leg, steps: steps, description: description, timeout: setButtonTimeout, observer: observer)

      return (link, .setButton)

    }

    do {

      let link: AllLinkingCompleted = try await linker.linkModemFirst(
        device,
        modemRole: leg.modemRole,
        modemGroup: leg.modemGroup,
        deviceGroup: leg.deviceGroup,
        deviceAcknowledged: { () async -> Void in

          await observer.linking(.hubLinkingLegJoined(leg, by: .enterLinkingMode))

        }
      )

      return (link, .enterLinkingMode)

    } catch let error as CancellationError {

      throw error

    } catch let LinkingError.unexpectedLink(link) {

      if let mismatch = LinkMismatch(link, direction: .linking, device: device) {

        throw mismatch

      }

      throw LinkingError.unexpectedLink(link)

    } catch {

      // A first leg falls back to the SET button, as a device without legs does, even when
      // the catalog says Enter Linking Mode works, which the fallback says, and so does a later
      // leg of a device that can't take Enter Linking Mode at all. Any other failure of a later
      // leg is reported, since the device is linked to the modem by then.
      let isUnsupported: Bool = (error as? LinkingError) == .remoteLinkingUnsupported(device)

      guard leg.isFirst || isUnsupported else {

        throw error

      }

      await observer.linking(.fallback(.setButtonLeg(leg, reason: error)))

      let link: AllLinkingCompleted = try await linkBySETButton(leg, steps: steps, description: description, timeout: setButtonTimeout, observer: observer)

      return (link, .setButton)

    }

  }

  /// Makes a leg's link with the device's SET button: the modem starts ALL-Linking in the
  /// leg's role and group, then the observer is told to have the SET button pressed, and only
  /// the device's link is accepted.
  private func linkBySETButton(
    _ leg: HubLinkingLeg,
    steps: [DeviceLifecycle.Step],
    description: DeviceDescription?,
    timeout: Duration,
    observer: any LinkingObserver
  ) async throws -> AllLinkingCompleted {

    let prompt = SETButtonPrompt(
      direction: .linking,
      group: leg.modemGroup,
      timeout: timeout,
      device: leg.device,
      deviceDescription: description,
      steps: steps,
      modemRole: leg.modemRole,
      deviceGroup: leg.deviceGroup
    )

    return try await makeLinker().linkManually(
      as: Self.manualRole(leg.modemRole),
      group: leg.modemGroup,
      device: leg.device,
      timeout: timeout,
      ready: { () async -> Void in

        await observer.linking(.pressSETButton(prompt))

      }
    )

  }

  // MARK: - Keeping a device awake

  /// The operating flags a linking flow may write: those the catalog's messages that keep the
  /// device awake and let it sleep again name, and the command set's
  /// ``CommandSet/linkingChanges``. Every flag a linking flow writes is checked against them.
  ///
  /// - Parameter description: What the catalog says about the device, if it's known.
  /// - Returns: The flags' names.
  static func writableLinkingFlags(of description: DeviceDescription?) -> Set<SettingName> {

    let commands: CommandSet? = description?.commandSet
    var flags = Set<SettingName>(commands?.linkingChanges.map(\.flag) ?? [])

    if let keepAwake = description?.hubLinking?.keepAwake {

      for message in [keepAwake.send, keepAwake.release].compactMap({ $0 }) {

        if let flag = flagWritten(by: message, in: commands) {

          flags.insert(flag)

        }

      }

    }

    return flags

  }

  /// The operating flag a message writes, if it writes one: the flag it names, or the flag
  /// whose Set Operating Flags cmd2 it sends.
  ///
  /// - Parameters:
  ///   - message: The message.
  ///   - commands: The device's command set, if the catalog gives one.
  /// - Returns: The flag's name, or `nil` for a message that writes no flag the command set
  ///   names.
  static func flagWritten(by message: DeviceLifecycle.HubLinking.HubMessage, in commands: CommandSet?) -> SettingName? {

    let setOperatingFlags: UInt8 = DeviceSettingSafety.setOperatingFlagsCommand1
    let command: Command?

    switch message {
    case let .flag(condition):
      return condition.flag
    case let .bytes(raw):
      command = raw.command
    case let .command(name):
      if let flagCommand = commands?.flagCommands.first(where: { (entry: OperatingFlagCommand) -> Bool in entry.name == name }) {

        command = flagCommand.command.command

      } else if let standard = commands?.standardCommand(named: name), case let .fixed(command2) = standard.command2 {

        command = Command(command1: standard.command1, command2: command2)

      } else {

        command = nil

      }
    }

    guard let command, command.command1 == setOperatingFlags else {

      return nil

    }

    return commands?.operatingFlags.first { (flag: OperatingFlag) -> Bool in

      flag.on == command.command2 || flag.off == command.command2

    }?.name

  }

  /// Sends the message that keeps a device awake through its guarded send path, and tells the
  /// observer. It isn't sent when the message that lets the device sleep again never would be.
  ///
  /// - Returns: Whether the message may have reached the device, so it's to be let sleep again:
  ///   `false` only when it was refused before anything was sent.
  /// - Throws: `CancellationError` if the task is canceled.
  private func sendKeepAwake(
    _ keepAwake: DeviceLifecycle.HubLinking.KeepAwake,
    to device: InsteonAddress,
    writableFlags: Set<SettingName>,
    observer: any LinkingObserver
  ) async throws -> Bool {

    await observer.linking(.keepAwake(.sending(device, timing: keepAwake.timing)))

    do {

      let target: Device = network.device(device)

      // A device that couldn't be let sleep again isn't kept awake.
      try await target.refuseKeepAwakeWithoutRelease(keepAwake, writableFlags: writableFlags)
      try await target.sendLinkingMessage(keepAwake.send, duration: keepAwake.duration, writableFlags: writableFlags)
      await observer.linking(.keepAwake(.sent(device)))

      return true

    } catch let error as CancellationError {

      throw error

    } catch let error as DeviceControlError {

      // Refused before anything was sent.
      await observer.linking(.keepAwake(.notSent(device, reason: error)))

      return false

    } catch let error as FieldError {

      await observer.linking(.keepAwake(.notSent(device, reason: error)))

      return false

    } catch {

      await observer.linking(.keepAwake(.notSent(device, reason: error)))

      return true

    }

  }

  /// Sends the message that lets a device sleep again, when the catalog gives one, through its
  /// guarded send path, and tells the observer. It never throws: linking is over either way.
  ///
  /// A canceled task can't send anything, and this one can be canceled while it sends. So a
  /// task of its own, which canceling this one doesn't reach, always sends it while this one
  /// waits, rather than leaving the device awake and draining its batteries.
  private func releaseKeepAwake(
    _ keepAwake: DeviceLifecycle.HubLinking.KeepAwake?,
    of device: InsteonAddress,
    writableFlags: Set<SettingName>,
    observer: any LinkingObserver
  ) async {

    guard let release = keepAwake?.release else {

      return

    }

    let network: DeviceNetwork = self.network
    let send: @Sendable () async -> Void = { () async -> Void in

      await observer.linking(.keepAwake(.releasing(device)))

      do {

        try await network.device(device).sendLinkingMessage(release, duration: nil, writableFlags: writableFlags)
        await observer.linking(.keepAwake(.released(device)))

      } catch {

        await observer.linking(.keepAwake(.notReleased(device, reason: error)))

      }

    }

    // Unstructured, so cancellation that arrives while it sends doesn't stop it.
    await Task { await send() }.value

  }

  /// The SET button linking role for the modem's role in a link.
  static func manualRole(_ role: ModemRole) -> ManualLinkingRole {

    switch role {
    case .controller:
      return .controller
    case .responder:
      return .responder
    }

  }

}
