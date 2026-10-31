import InsteonCore

/// What `insteon link` and `insteon unlink` tell the person to do, and in which order.
///
/// The controller of a link goes first. When the modem is the controller, it enters linking
/// or unlinking mode, then the person presses the device's SET button. When the modem is the
/// responder, the device is the controller, so the person puts it into its mode first, then
/// the modem joins, as Insteon's own steps say.
public enum LinkingInstructions {

  /// Whether a link is being made or removed.
  public enum Mode: Hashable, Sendable {

    /// A link is being made.
    case linking

    /// A link is being removed.
    case unlinking

  }

  /// The steps of one of a device's procedures that are done on the device itself, each with
  /// what the device does in answer, such as
  /// `"Press and hold the SET button until the module beeps. [LED blinks green]"`.
  ///
  /// - Parameter procedure: The procedure, such as the profile's lifecycle `linking`.
  /// - Returns: The steps, in order.
  public static func steps(of procedure: Instructions) -> [String] {

    steps(procedure.steps.filter { !$0.isOnOtherDevice })

  }

  /// Steps done on a device, each with what the device does in answer, such as
  /// `"Press and hold the SET button until the module beeps. [LED blinks green]"`.
  ///
  /// - Parameter steps: The steps, such as a `SETButtonPrompt`'s.
  /// - Returns: The steps, in order.
  public static func steps(_ steps: [InstructionStep]) -> [String] {

    steps.map { (step: InstructionStep) -> String in

      step.expectation.map { "\(step.text) [\($0)]" } ?? step.text

    }

  }

  /// A device's address, then its product's name and model in parentheses when the catalog
  /// has its profile, such as `"1A.2B.3C (Dimmer Switch 2477D)"`, to name it in a sentence.
  ///
  /// The product's alias is left out, so the parentheses don't nest.
  ///
  /// - Parameters:
  ///   - device: The device's address.
  ///   - profile: The catalog's profile for the device, or `nil` if it isn't known.
  /// - Returns: The label.
  public static func deviceLabel(_ device: InsteonAddress, info: DeviceInfo?) -> String {

    guard let name = info?.productName, let model = info?.model else {

      return "\(device)"

    }

    return "\(device) (\(name) \(model))"

  }

  /// What to tell the person before the modem joins a device as its responder: put the
  /// device into its mode first, then press Return.
  ///
  /// - Parameters:
  ///   - mode: Whether the device is to link or unlink.
  ///   - device: The device, as ``deviceLabel(_:info:)`` writes it, such as
  ///     `"1A.2B.3C (Dimmer Switch 2477D)"`, or `nil` for any device.
  ///   - steps: The device's own steps for the mode, from ``steps(of:)``, or empty if the
  ///     catalog doesn't have them.
  ///   - waitsForReturn: Whether the command waits for Return before starting the modem,
  ///     which it does when it reads from a terminal.
  /// - Returns: The lines, in order.
  public static func deviceFirst(_ mode: Mode, device: String?, steps: [String], waitsForReturn: Bool) -> [String] {

    let target = device ?? "the device"
    var lines: [String]

    switch (mode, steps.isEmpty) {
    case (.linking, true):
      lines = ["First put \(target) into linking mode: press and hold its SET button until it beeps or its light blinks."]
    case (.unlinking, true):
      lines = [
        "First put \(target) into unlinking mode. On most devices, press and hold the SET button until it beeps, "
          + "then press and hold it again until it beeps again; the device's manual has its steps."
      ]
    case (.linking, false), (.unlinking, false):
      lines = ["First put \(target) into \(mode == .linking ? "linking" : "unlinking") mode:"]
      lines += steps.enumerated().map { "  \($0.offset + 1). \($0.element)" }
    }

    lines.append(
      waitsForReturn
        ? "Then press Return, and the modem joins as its responder."
        : "The modem joins as its responder now."
    )

    return lines

  }

  /// What to tell the person once the modem, as the controller, is in its mode: press the
  /// device's SET button.
  ///
  /// - Parameters:
  ///   - mode: Whether the modem is linking or unlinking.
  ///   - group: The modem's group.
  ///   - seconds: How long the command waits.
  ///   - device: The device, or `nil` for any device.
  ///   - steps: The device's own steps to link, from ``steps(of:)``, or empty if the catalog
  ///     doesn't have them. A responder unlinks with its linking steps too.
  ///   - modemRole: The modem's role, for a leg of the catalog's linking from a Hub. Defaults
  ///     to `nil`.
  ///   - deviceGroup: The device's group the leg links. Defaults to `nil`.
  /// - Returns: The lines, in order.
  public static func modemFirst(
    _ mode: Mode,
    group: AllLinkGroupNumber,
    seconds: Int64,
    device: String?,
    steps: [String],
    modemRole: ModemRole? = nil,
    deviceGroup: AllLinkGroupNumber? = nil
  ) -> [String] {

    let target = device ?? "the device"
    let modemMode = mode == .linking ? "linking" : "unlinking"
    var lines = ["The modem is in \(modemMode) mode for group \(group)."]

    if let modemRole, let deviceGroup {

      let role: String = modemRole == .controller ? "controller" : "responder"

      lines = ["The modem is in \(modemMode) mode as \(role) of group \(group), for the device's group \(deviceGroup)."]

    }

    if steps.isEmpty {

      lines.append("Now press and hold the SET button of \(target) until it beeps or its light blinks.")

    } else {

      lines.append("Now, on \(target):")
      lines += steps.enumerated().map { "  \($0.offset + 1). \($0.element)" }

    }

    lines.append("Waiting up to \(seconds) seconds; Control-C stops.")

    return lines

  }

  /// What to tell the person before one link is removed without the device's SET button.
  ///
  /// - Parameters:
  ///   - modemRole: The modem's role in the link.
  ///   - device: The device, as ``deviceLabel(_:info:)`` writes it.
  ///   - group: The link's group: the modem's when it's the controller, the device's when
  ///     it's the responder.
  /// - Returns: The line.
  public static func remoteUnlinking(modemRole: ModemRole, device: String, group: AllLinkGroupNumber) -> String {

    switch modemRole {
    case .controller:
      return "Removing \(device) from the modem's group \(group): the modem starts ALL-Linking in unlinking mode "
        + "and sends the device Enter Linking Mode..."
    case .responder:
      return "Removing the modem from \(device)'s group \(group): the device is sent Enter Unlinking Mode, "
        + "and the modem joins as responder..."
    }

  }

  /// What to tell the person when links couldn't be removed without the device's SET button:
  /// how to put the device into unlinking mode for the commands that remove each link that's
  /// left.
  ///
  /// - Parameters:
  ///   - device: The device, as ``deviceLabel(_:info:)`` writes it.
  ///   - steps: The device's own steps to unlink, from ``steps(of:)``, or empty if the catalog
  ///     doesn't have them.
  /// - Returns: The lines, in order.
  public static func setButtonUnlinking(device: String, steps: [String]) -> [String] {

    guard !steps.isEmpty else {

      return [
        "Remove the links that are left with the SET button of \(device). On most devices, unlinking mode is: "
          + "press and hold the SET button until it beeps, then press and hold it again until it beeps again."
      ]

    }

    let numbered: [String] = steps.enumerated().map { (step: (offset: Int, element: String)) -> String in

      "  \(step.offset + 1). \(step.element)"

    }

    return ["Remove the links that are left with the SET button of \(device). To put it into unlinking mode:"] + numbered

  }

  /// What to tell the person when a light or switched load doesn't turn on with Light On before
  /// it links, as when an i2CS device rejects the command because it isn't linked to the modem.
  ///
  /// The device links in the state it's in, so its on-level matches that state. Once it's
  /// linked, running `insteon link` for it again turns it on first and rewrites its on-level
  /// to full on.
  ///
  /// - Parameters:
  ///   - device: The device's address.
  ///   - reason: Why the device didn't turn on, as a sentence that ends with a period.
  /// - Returns: A message that names the device, gives the reason, and says how to give it
  ///   full on as its on-level.
  public static func didNotTurnOnBeforeLinking(_ device: InsteonAddress, reason: String) -> String {

    "\(device) didn't turn on: \(reason) It links in the state it's in, so its on-level matches that state. "
      + "To give it full on, run 'insteon link \(device)' again once it's linked, or turn it on at the device before linking."

  }

}

/// Explains a link the modem reported that isn't the one asked for.
public enum LinkOutcome {

  /// Why a link the modem reported isn't the one asked for, or `nil` if it is, as
  /// `InsteonErrorDescription.linkMismatch(_:direction:device:)` words it.
  ///
  /// - Parameters:
  ///   - link: The modem's report.
  ///   - mode: Whether a link was being made or removed.
  ///   - device: The device asked for, or `nil` for any device.
  /// - Returns: A message that says what happened and what to do, or `nil` if the link is the
  ///   one asked for.
  public static func mismatch(_ link: LinkMade, mode: LinkingInstructions.Mode, device: InsteonAddress?) -> String? {

    let direction: LinkingDirection = mode == .linking ? .linking : .unlinking

    return InsteonErrorDescription.linkMismatch(link, direction: direction, device: device)

  }

}

/// What `insteon link`, `insteon unlink` and `insteon remove` tell the person about each step
/// a `DeviceLinkingCoordinator` takes, on standard error.
public enum LinkingEventText {

  /// The notes for an event, in order, or none for an event the command reports as a result,
  /// such as a link made, a device forgotten or kept, the modem's records deleted for it, the
  /// records other devices hold for it, and its factory reset steps, which `RemovalText` words.
  ///
  /// - Parameters:
  ///   - event: The event.
  ///   - message: The sentence that describes an error, ending with a period.
  /// - Returns: The notes.
  public static func notes(for event: LinkingEvent, message: (any Error) -> String) -> [String] {

    switch event {
    case let .identifying(device):
      return ["Asking \(device) for its identity with ID Request..."]
    case let .notIdentifiedBeforeLinking(device, reason):
      let why: String

      switch reason {
      case .notLinked:
        why = "\(device) won't say what it is until it's linked to the modem, as an i2CS device does"
      case .noIdentity:
        why = "\(device) didn't report its identity"
      case let .failed(error):
        why = "\(device) couldn't be asked for its identity: \(message(error).dropLast())"
      }

      return ["\(why), so it's linked as a device the Insteon device catalog doesn't describe."]
    case let .turningOnBeforeLinking(device):
      return ["Turning \(device) on with Light On first, so it links with full on as its on-level..."]
    case let .notTurnedOnBeforeLinking(device, reason):
      return [LinkingInstructions.didNotTurnOnBeforeLinking(device, reason: message(reason))]
    case let .notTurningOnBeforeLinking(device):
      return [
        "Not turning \(device) on first: the catalog doesn't identify it as a light or switched load, "
          + "so it links with whatever on-level it captures."
      ]
    case let .linkingRemotely(device, modemRole):
      return [
        "Linking \(device) without its SET button: the modem starts ALL-Linking as \(role(modemRole)) "
          + "and sends the device Enter Linking Mode..."
      ]
    case let .fallback(.setButtonLinking(device, reason)):
      return ["\(device) didn't link remotely: \(message(reason)) Link it with its SET button instead."]
    case let .fallback(.setButtonLeg(leg, reason)):
      guard leg.isRemoteLinkingExpectedToWork else {

        return ["\(leg.device) didn't link remotely: \(message(reason)) Link it with its SET button instead."]

      }

      return [
        "\(leg.device) didn't link remotely, though the Insteon device catalog says it takes Enter Linking Mode: \(message(reason)) "
          + "Link it with its SET button instead."
      ]
    case let .fallback(.setButtonUnlinking(device, description, steps)):
      return LinkingInstructions.setButtonUnlinking(
        device: LinkingInstructions.deviceLabel(device, info: description),
        steps: LinkingInstructions.steps(steps)
      )
    case let .pressSETButton(prompt):
      return LinkingInstructions.modemFirst(
        mode(prompt.direction),
        group: prompt.group,
        seconds: prompt.timeout.components.seconds,
        device: prompt.device.map { (device: InsteonAddress) -> String in

          LinkingInstructions.deviceLabel(device, info: prompt.info)

        },
        steps: LinkingInstructions.steps(prompt.steps),
        modemRole: prompt.modemRole,
        deviceGroup: prompt.deviceGroup
      )
    case let .modemJoining(timeout):
      return ["The modem is joining as responder. Waiting up to \(timeout.components.seconds) seconds; Control-C stops."]
    case let .linkingBack(device, group):
      return ["Linking back: sending \(device) Enter Linking Mode for its group \(group), so the modem becomes its responder..."]
    case .linked, .unlinked, .unlinkedAll:
      return []
    case let .hubLinkingLegStarted(leg):
      return [
        "\(legName(leg)): the modem starts ALL-Linking as \(role(leg.modemRole)) of group \(leg.modemGroup), "
          + "for \(leg.device)'s group \(leg.deviceGroup)..."
      ]
    case let .hubLinkingLegJoined(leg, join):
      switch join {
      case .enterLinkingMode:
        return ["\(leg.device) took Enter Linking Mode for its group \(leg.deviceGroup); waiting for the modem to report the link..."]
      case .deviceFirst:
        return ["\(leg.device) is in linking mode."]
      case .setButton:
        return []
      }
    case .hubLinkingLegCompleted:
      return []
    case let .hubLinkingLegFailed(leg, reason, notRun):
      return legFailed(leg, reason: message(reason), notRun: notRun.count, canRetry: HubLinkingLeg.canSucceedOnRetry(after: reason))
    case let .hubLinkingStopped(result, reason):
      let linked: Int = result.legs.filter { (outcome: HubLinkingLegOutcome) -> Bool in outcome.link != nil }.count
      let count: Int = result.legs.count

      return ["Linking stopped after \(linked) of \(count) legs: \(message(reason)) The links made stay made."]
    case let .keepAwake(keepAwake):
      return keepAwakeNotes(keepAwake, message: message)
    case let .allGroupsWhen(leg, condition):
      let state: String = condition.isSet ? "on" : "off"
      let otherState: String = condition.isSet ? "off" : "on"

      return [
        "\(legName(leg)) links every group \(leg.device) controls while its \(condition.flag) setting is \(state). "
          + "The setting isn't read or changed here; with it \(otherState), each group needs a link of its own."
      ]
    case let .readingModemLinks(device, purpose):
      switch purpose {
      case .findingLinksToRemove:
        return ["Reading the modem's ALL-Link database for \(device)'s links..."]
      case .findingGroupToUnlink:
        return ["Reading the modem's ALL-Link database for \(device)'s groups..."]
      }
    case let .unlinkGroupChosen(device, group, isFromModemRecords):
      return [
        isFromModemRecords
          ? "The modem's records link \(device) in group \(group), so the unlink uses it."
          : "The modem has no record for \(device) in that role, so the unlink uses group \(group)."
      ]
    case let .unlinkingRemotely(device, description, link):
      return [
        LinkingInstructions.remoteUnlinking(
          modemRole: link.modemRole,
          device: LinkingInstructions.deviceLabel(device, info: description),
          group: link.group
        )
      ]
    case let .linksRemaining(device, links):
      return links.map { (link: ModemLink) -> String in

        let roleOption: String = link.modemRole == .controller ? "" : " --responder"

        return "\(device) still has links in group \(link.group); run 'insteon unlink \(device) --group \(link.group)\(roleOption)'."

      }
    case let .remainingLinksUnknown(device, reason):
      return ["Couldn't check the modem for \(device)'s other links: \(message(reason))"]
    case let .deletingModemRecords(device, reason):
      return [
        "\(RemovalText.deletionReason(device, reason, message: message)) So the modem's records for it are being deleted "
          + "with Manage ALL-Link Record, as --force-modem-side asks. The device keeps its own records."
      ]
    case let .scanningDatabase(device, removedDevice):
      return ["Reading \(device)'s ALL-Link database for records that name \(removedDevice)..."]
    case .forgotten, .leftoverRecords, .factoryReset, .modemRecordsDeleted, .kept:
      return []
    }

  }

  /// What to tell the person when a leg of the catalog's linking from a Hub didn't link.
  ///
  /// - Parameters:
  ///   - leg: The leg.
  ///   - reason: Why it didn't link, as a sentence that ends with a period.
  ///   - notRun: How many legs after it weren't run.
  ///   - canRetry: Whether linking again may help, as
  ///     `HubLinkingLeg.canSucceedOnRetry(after:)` says, so the person is told to.
  /// - Returns: The lines, in order.
  public static func legFailed(_ leg: HubLinkingLeg, reason: String, notRun: Int, canRetry: Bool) -> [String] {

    var line: String = "\(legName(leg)) didn't link: \(reason)"

    if leg.isRemoteLinkingExpectedToWork {

      line += " The Insteon device catalog says \(leg.device) takes Enter Linking Mode, so check that it's powered and in range, "
        + "and that no other device is in linking mode."

    }

    var lines: [String] = [line]

    if notRun > 0 {

      let notRunText: String = "\(notRun == 1 ? "The leg" : "The \(notRun) legs") after it \(notRun == 1 ? "wasn't" : "weren't") run"

      lines.append(
        canRetry
          ? notRunText + "; run 'insteon link \(leg.device)' again to link \(notRun == 1 ? "it" : "them")."
          : notRunText + "."
      )

    }

    return lines

  }

  /// Why `insteon link` fails after linking some of a device's legs of the catalog's linking
  /// from a Hub, or `nil` when every leg linked or there were none.
  ///
  /// - Parameters:
  ///   - result: What the coordinator linked.
  ///   - message: The sentence that describes an error, ending with a period.
  /// - Returns: The message.
  public static func incompleteLegs(_ result: DeviceLinkingResult, message: (any Error) -> String) -> String? {

    guard let failed = result.failedLeg, let reason = failed.failure else {

      return nil

    }

    let linked: Int = result.legs.filter { (outcome: HubLinkingLegOutcome) -> Bool in outcome.link != nil }.count

    let summary: String = "\(failed.leg.device) linked \(linked) of its \(failed.leg.count) legs; \(legName(failed.leg).lowercased()) didn't link: "
      + message(reason)

    // Advise linking again only where it may help, such as after a timeout.
    guard HubLinkingLeg.canSucceedOnRetry(after: reason) else {

      return summary

    }

    return summary + " Run 'insteon link \(failed.leg.device)' again to link the rest."

  }

  /// The notes for keeping a battery-powered device awake while it links, and letting it sleep
  /// again.
  private static func keepAwakeNotes(_ event: KeepAwakeEvent, message: (any Error) -> String) -> [String] {

    switch event {
    case let .sending(device, _):
      return ["Keeping \(device) awake while it links, as the Insteon device catalog says..."]
    case .sent, .released:
      return []
    case let .notSent(device, reason):
      return ["\(device) wasn't kept awake: \(message(reason)) Linking goes on; if it falls asleep, wake it and run the command again."]
    case let .releasing(device):
      return ["Letting \(device) sleep again..."]
    case let .notReleased(device, reason):
      return [
        "\(device) wasn't let sleep again: \(message(reason)) It may stay awake and use its batteries until it sleeps on its own "
          + "or is woken and linked again."
      ]
    }

  }

  /// What to tell the person before the modem keeps a battery-powered device awake: wake it,
  /// then press Return.
  ///
  /// - Parameters:
  ///   - prompt: The device, with the catalog's steps to wake it.
  ///   - waitsForReturn: Whether the command waits for Return, which it does when it reads
  ///     from a terminal.
  /// - Returns: The lines, in order.
  public static func wake(_ prompt: WakePrompt, waitsForReturn: Bool) -> [String] {

    let target: String = LinkingInstructions.deviceLabel(prompt.device, info: prompt.info)
    let steps: [String] = LinkingInstructions.steps(prompt.steps)
    var lines: [String]

    if steps.isEmpty {

      lines = ["First wake \(target); its manual says how, such as by pressing one of its buttons."]

    } else {

      lines = ["First wake \(target):"]
      lines += steps.enumerated().map { "  \($0.offset + 1). \($0.element)" }

    }

    lines.append(
      waitsForReturn
        ? "Then press Return, and the modem keeps it awake while it links."
        : "The modem keeps it awake while it links now."
    )

    return lines

  }

  /// A leg's name in a sentence, such as `"Leg 2 of 3"`.
  ///
  /// - Parameter leg: The leg.
  /// - Returns: The name.
  public static func legName(_ leg: HubLinkingLeg) -> String {

    "Leg \(leg.index + 1) of \(leg.count)"

  }

  /// What to tell the person before the modem joins a device as its responder: put the device
  /// into its mode first, then press Return.
  ///
  /// - Parameters:
  ///   - prompt: What the device is to do.
  ///   - waitsForReturn: Whether the command waits for Return before starting the modem,
  ///     which it does when it reads from a terminal.
  /// - Returns: The lines, in order.
  public static func deviceFirst(_ prompt: DeviceFirstPrompt, waitsForReturn: Bool) -> [String] {

    LinkingInstructions.deviceFirst(
      mode(prompt.direction),
      device: prompt.device.map { (device: InsteonAddress) -> String in

        LinkingInstructions.deviceLabel(device, info: prompt.info)

      },
      steps: LinkingInstructions.steps(prompt.steps),
      waitsForReturn: waitsForReturn
    )

  }

  /// The instructions' mode for a direction.
  private static func mode(_ direction: LinkingDirection) -> LinkingInstructions.Mode {

    switch direction {
    case .linking:
      return .linking
    case .unlinking:
      return .unlinking
    }

  }

  /// The modem's role as the command names it.
  private static func role(_ role: ModemRole) -> String {

    switch role {
    case .controller:
      return "controller"
    case .responder:
      return "responder"
    }

  }

}
