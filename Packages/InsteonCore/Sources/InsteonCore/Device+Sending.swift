import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

// Sending the device messages through the guard every send path shares.
extension Device {

  /// What a message is sent for, which says how a refusal to send it is reported.
  enum SendPurpose {

    /// An operation, refused with ``DeviceControlError/unsupported(_:product:)``.
    case control(DeviceOperation)

    /// Writing a setting, refused with ``DeviceSettingError/neverWritten(label:)``.
    case setting(label: String)

    /// A message sent as it's given, through a raw passthrough, refused with the
    /// ``SendRefusal`` itself.
    case asGiven

    /// Whether the message's bytes are sent as they're given, rather than built and checked
    /// against what the device reported, so any guarded flag in a byte it writes refuses it.
    var sendsBytesAsGiven: Bool {

      switch self {
      case .asGiven, .control(.keepAwake):
        return true
      case .control, .setting:
        return false
      }

    }

  }

  /// A message the catalog's linking from a Hub names, resolved to what's sent, once every
  /// guard allows it.
  enum LinkingSend {

    /// A standard message.
    case standard(StandardMessage)

    /// An extended message.
    case extended(ExtendedMessage)

    /// Set Operating Flags with a cmd2, in the form the device takes.
    case setOperatingFlags(UInt8, extendedWhen: SettingName?, description: DeviceDescription, commands: CommandSet)

  }

  /// Sends a message the catalog's linking from a Hub names, such as the one that keeps a
  /// battery-powered device awake while it links, through the same guards as every other
  /// message the device is sent.
  ///
  /// A command set entry gives the bytes: a flag command, or a standard or extended command,
  /// with `duration`'s whole seconds, or else its parameter's largest value, for a parameter;
  /// or an operating flag, set or cleared with Set Operating Flags in the form the device takes.
  /// A message given by its bytes is sent as given. Nothing else is written: no other flag,
  /// and never one the catalog or the floor guards, nor a command the catalog never sends.
  ///
  /// - Parameters:
  ///   - message: The message.
  ///   - duration: How long the message keeps the device awake, if the catalog says.
  ///   - writableFlags: The operating flags a linking flow may write.
  /// - Throws: ``DeviceControlError/unsupported(_:product:)`` for a message that's never
  ///   sent, ``DeviceControlError/missingCommand(_:product:)`` for one the command set
  ///   doesn't describe, `FieldError` for a parameter that doesn't fit, and the modem's
  ///   errors.
  func sendLinkingMessage(_ message: DeviceLifecycle.HubLinking.HubMessage, duration: Duration?, writableFlags: Set<SettingName>) async throws {

    let purpose: SendPurpose = .control(.keepAwake)

    switch try await resolveLinkingMessage(message, duration: duration, writableFlags: writableFlags) {
    case let .standard(standard):
      _ = try await request(standard, timeout: network.requestTimeout, for: purpose)
    case let .extended(extended):
      _ = try await request(extended, timeout: Modem.defaultExtendedRequestTimeout, for: purpose)
    case let .setOperatingFlags(command2, extendedWhen, description, commands):
      try await sendSetOperatingFlags(command2, extendedWhen: extendedWhen, description: description, commands: commands, purpose: purpose)
    }

    await network.recordAnswer(of: address, level: nil)

  }

  /// Refuses to keep a device awake when the message that lets it sleep again would be
  /// refused, for any reason ``sendLinkingMessage(_:duration:writableFlags:)`` refuses one, so
  /// it isn't left awake, draining its batteries. Nothing is sent.
  ///
  /// - Parameters:
  ///   - keepAwake: How the catalog keeps the device awake.
  ///   - writableFlags: The operating flags a linking flow may write.
  /// - Throws: The refusal the release would get: ``DeviceControlError`` or `FieldError`.
  func refuseKeepAwakeWithoutRelease(_ keepAwake: DeviceLifecycle.HubLinking.KeepAwake, writableFlags: Set<SettingName>) async throws {

    guard let release = keepAwake.release else {

      return

    }

    _ = try await resolveLinkingMessage(release, duration: nil, writableFlags: writableFlags)

  }

  /// What a message the catalog's linking from a Hub names sends, once every guard allows it,
  /// without sending anything: the flags a linking flow may write, the command set's guards
  /// and the byte floor, by the bytes the message carries.
  func resolveLinkingMessage(_ message: DeviceLifecycle.HubLinking.HubMessage, duration: Duration?, writableFlags: Set<SettingName>) async throws -> LinkingSend {

    let description: DeviceDescription? = await network.registry.device(address)?.deviceDescription
    let commands: CommandSet? = description?.commandSet
    let product: String = description.map { (described: DeviceDescription) -> String in DeviceControlModel.product(of: described) } ?? "this device"
    let refused = DeviceControlError.unsupported(.keepAwake, product: product)
    let purpose: SendPurpose = .control(.keepAwake)

    // A linking flow writes only the flags the catalog lets it. The registry can change while
    // a device links, so a flag outside them is refused rather than asserted.
    if let written = DeviceLinkingCoordinator.flagWritten(by: message, in: commands) {

      guard writableFlags.contains(written) else {

        throw refused

      }

    }

    let resolved: LinkingSend

    switch message {
    case let .bytes(raw):
      if raw.isExtended {

        // A message given by its bytes never writes the device's extended settings: which
        // bits they hold is the command set's to say, through a command it names.
        if raw.command == Command(command1: 0x2E, command2: 0x00), raw.fixedBytes.contains(where: { (byte: FixedUserDataByte) -> Bool in byte.position == 2 && byte.value != 0x00 }) {

          throw refused

        }

        var userData = UserData()

        for byte in raw.fixedBytes {

          userData[byte.position] = byte.value

        }

        resolved = .extended(ExtendedMessage(to: address, command: raw.command, userData: userData, integrity: raw.integrity.scheme))

      } else {

        resolved = .standard(StandardMessage(to: address, command: raw.command))

      }

    case let .flag(condition):
      guard let commands, let description, let flag = commands.operatingFlag(named: condition.flag) else {

        throw DeviceControlError.missingCommand(condition.flag.rawValue, product: product)

      }

      // A kept flag is never written, and a never-set flag is only cleared.
      switch DeviceSettingSafety.rule(for: flag) {
      case .keep?:
        throw refused
      case .neverSet? where condition.isSet:
        throw refused
      default:
        break
      }

      guard let change = commands.change(for: flag, setting: condition.isSet), !DeviceSettingSafety.sendsNeverSentCommand(change, in: commands) else {

        throw refused

      }

      switch change {
      case let .setOperatingFlags(command2):
        resolved = .setOperatingFlags(command2, extendedWhen: flag.extendedWhen, description: description, commands: commands)
      case let .standardCommand(command):
        resolved = .standard(StandardMessage(to: address, command: try command.command()))
      }

    case let .command(name):
      guard let commands, let description else {

        throw DeviceControlError.missingCommand(name.rawValue, product: product)

      }

      if let flagCommand = commands.flagCommands.first(where: { (entry: OperatingFlagCommand) -> Bool in entry.name == name }) {

        guard !DeviceSettingSafety.isNeverSent(flagCommand.sendGuard), !DeviceSettingSafety.neverSentNames.contains(name) else {

          throw refused

        }

        resolved = .setOperatingFlags(flagCommand.command.command.command2, extendedWhen: flagCommand.extendedWhen, description: description, commands: commands)

      } else if let standard = commands.standardCommand(named: name) {

        guard DeviceSettingSafety.isSendable(standard, in: commands) else {

          throw refused

        }

        let command: Command

        switch standard.command2 {
        case .fixed:
          command = try standard.command()
        case let .parameter(field):
          command = try standard.command(Self.durationValue(duration, for: field))
        }

        resolved = .standard(StandardMessage(to: address, command: command))

      } else if let extended = commands.extendedCommand(named: name) {

        guard DeviceSettingSafety.isSendable(extended, in: commands) else {

          throw refused

        }

        let takesDuration: MessageField? = Self.durationParameter(of: extended)
        var values: [SettingName: FieldValue] = [:]

        // Only the parameter that takes the duration gets it; any other is zero.
        for parameter in extended.parameters {

          values[parameter.name] = parameter == takesDuration ? Self.durationValue(duration, for: parameter) : Self.zeroValue(for: parameter)

        }

        resolved = .extended(try extended.message(to: address, values: values))

      } else {

        throw DeviceControlError.missingCommand(name.rawValue, product: product)

      }
    }

    // The bytes the message carries pass the same check as every message the device is sent.
    switch resolved {
    case let .standard(standard):
      try await refuseIfNeverSent(standard.command, for: purpose)
    case let .extended(extended):
      try await refuseIfNeverSent(extended.command, userData: extended.userData, for: purpose)
    case let .setOperatingFlags(command2, _, _, _):
      try await refuseIfNeverSent(Command(command1: DeviceSettingSafety.setOperatingFlagsCommand1, command2: command2), for: purpose)
    }

    return resolved

  }

  /// Sends a message as it's given, through the guards every message the device is sent
  /// passes, then collects the other messages the device sends for a time.
  ///
  /// - Parameters:
  ///   - message: The message, whose ``DirectMessage/device`` is the device.
  ///   - duration: How long to collect what the device sends after its acknowledgment.
  ///   - onAcknowledgment: Called with the device's acknowledgment.
  /// - Returns: The other messages from the device, in order.
  /// - Throws: ``SendRefusal`` before anything is sent, and the modem's errors.
  func sendAsGiven(_ message: DirectMessage, collectingFor duration: Duration, onAcknowledgment: (ReceivedFrame) -> Void) async throws -> [ReceivedFrame] {

    let device: InsteonAddress = address
    let replies: AsyncStream<ModemReply> = await modem.replies()
    let acknowledgment: ReceivedMessage

    if let extended = message.extended {

      acknowledgment = try await request(extended, timeout: Modem.defaultExtendedRequestTimeout, for: .asGiven)

    } else {

      acknowledgment = try await request(StandardMessage(to: device, command: message.command), timeout: network.requestTimeout, for: .asGiven)

    }

    onAcknowledgment(ReceivedFrame(acknowledgment))

    let received: [ModemReply] = await ModemSession.collect(replies, within: duration, clock: network.clock)
    var skippedAcknowledgment = false
    var frames: [ReceivedFrame] = []

    for reply in received {

      guard case let .messageReceived(incoming) = reply, incoming.sender == device else {

        continue

      }

      // The acknowledgment comes through the stream too.
      if !skippedAcknowledgment, incoming == acknowledgment {

        skippedAcknowledgment = true
        continue

      }

      frames.append(ReceivedFrame(incoming))

    }

    return frames

  }

  /// The parameter of a keep-awake extended command that takes how long to stay awake: the
  /// one in seconds, or else its only number, or `nil` when neither says.
  static func durationParameter(of command: DeviceExtendedCommand) -> MessageField? {

    let numbers: [MessageField] = command.parameters.filter { (field: MessageField) -> Bool in

      if case .number = field.kind {

        return true

      }

      return false

    }

    let seconds: MessageField? = numbers.first { (field: MessageField) -> Bool in

      if case let .number(_, _, unit) = field.kind, unit == .seconds {

        return true

      }

      return false

    }

    return seconds ?? (numbers.count == 1 ? numbers[0] : nil)

  }

  /// A parameter's value whose bits are all zero, for a parameter a keep-awake message leaves
  /// as it is.
  static func zeroValue(for field: MessageField) -> FieldValue {

    switch field.kind {
    case .number:
      return .number(0)
    case .buttons:
      return .buttons([])
    case .enumeration:
      return .unnamed(0)
    case .flags:
      return .flags([])
    case .boolean:
      return .boolean(false)
    }

  }

  /// The value of a keep-awake command's parameter: `duration`'s whole seconds, or else the
  /// parameter's largest value, kept within the parameter's range.
  static func durationValue(_ duration: Duration?, for field: MessageField) -> FieldValue {

    let range: ClosedRange<Double> = field.range ?? 0...255
    let seconds: Double = duration.map { (duration: Duration) -> Double in Double(duration.components.seconds) } ?? range.upperBound

    return .number(min(max(seconds, range.lowerBound), range.upperBound))

  }

  /// The command set's Beep, if the device may be sent it.
  static func sendableBeep(in commands: CommandSet) -> DeviceStandardCommand? {

    guard let beep = commands.standardCommand(named: beepCommand), DeviceSettingSafety.isSendable(beep, in: commands) else {

      return nil

    }

    return beep

  }

  /// Refuses a message whose bytes are never sent to the device, as
  /// `DeviceSettingSafety.isNeverSent(_:in:)` says from its command set: Poke, a
  /// ``ProtectedCommand`` the command set doesn't name for a flag it doesn't guard, and the
  /// bytes the catalog's guards add; and, for a
  /// message sent as it's given, an extended message that writes a byte holding a guarded
  /// flag, as `DeviceSettingSafety.guardedFlagWritten(by:userData:in:)` finds it, or any
  /// extended Set to a device with no command set. Every
  /// message the device is sent is checked here, with the bytes it actually carries, so a
  /// command filled in with a value, or listed under another name, can't send them.
  func refuseIfNeverSent(_ command: Command, userData: UserData? = nil, for purpose: SendPurpose) async throws {

    let description: DeviceDescription? = await network.registry.device(address)?.deviceDescription
    let commands: CommandSet? = description?.commandSet
    let product: String = description.map { (described: DeviceDescription) -> String in DeviceControlModel.product(of: described) } ?? "this device"
    let refusal: SendRefusal

    let isNeverSent: Bool = DeviceSettingSafety.isNeverSent(command, in: commands)

    if isNeverSent, let protected = ProtectedCommand(command) {

      refusal = .protected(protected)

    } else if isNeverSent {

      refusal = .neverSentToDevice(product: product)

    } else if purpose.sendsBytesAsGiven, let userData, let commands, let label = DeviceSettingSafety.guardedFlagWritten(by: command, userData: userData, in: commands) {

      refusal = .writesGuardedFlags(label: label)

    } else if purpose.sendsBytesAsGiven, commands == nil, let userData, DeviceSettingSafety.isExtendedSet(command, userData: userData) {

      // Without a command set, which bits an extended Set writes, such as the programming
      // lock's in an open/close sensor's configuration byte, can't be told.
      refusal = .extendedSetWithoutCommandSet

    } else {

      return

    }

    switch purpose {
    case let .control(operation):
      throw DeviceControlError.unsupported(operation, product: product)
    case let .setting(label):
      throw DeviceSettingError.neverWritten(label: label)
    case .asGiven:
      throw refusal
    }

  }

  /// Sends a standard message once ``refuseIfNeverSent(_:userData:for:)`` allows it. Every
  /// standard message the device is sent goes through here.
  func request(_ message: StandardMessage, timeout: Duration, for purpose: SendPurpose) async throws -> ReceivedMessage {

    try await refuseIfNeverSent(message.command, for: purpose)

    return try await modem.request(message, timeout: timeout)

  }

  /// Sends an extended message once ``refuseIfNeverSent(_:userData:for:)`` allows it, by its
  /// cmd1, cmd2 and user data. Every extended message the device is sent goes through here.
  func request(_ message: ExtendedMessage, timeout: Duration, for purpose: SendPurpose) async throws -> ReceivedMessage {

    try await refuseIfNeverSent(message.command, userData: message.userData, for: purpose)

    return try await modem.request(message, timeout: timeout)

  }

  /// Sends an action's message, a standard one with the network's timeout and an extended one
  /// with the timeout for extended requests.
  func send(_ message: DeviceControlModel.ActionMessage, for operation: DeviceOperation) async throws {

    switch message {
    case let .standard(standard):
      _ = try await request(standard, timeout: network.requestTimeout, for: .control(operation))
    case let .extended(extended):
      _ = try await request(extended, timeout: Modem.defaultExtendedRequestTimeout, for: .control(operation))
    }

  }

  /// The device's model, its main group, and the command a command set lists by a name, for a
  /// command sent to the main group, such as Light On Fast.
  ///
  /// - Returns: The command, or `nil` when the catalog doesn't describe the device's commands,
  ///   so the one the Insteon protocol defines is sent.
  /// - Throws: ``DeviceControlError/unsupported(_:product:)`` when the command set doesn't list
  ///   the command, and the refusals of choosing the main group.
  func mainGroupCommand(
    _ name: SettingName,
    for operation: DeviceOperation
  ) async throws -> (DeviceControlModel, DeviceControlModel.Group, DeviceStandardCommand?) {

    let model: DeviceControlModel = try await controlModel()
    let target: DeviceControlModel.Group = try controlGroup(nil, in: model, for: operation)

    guard let commands = model.commandSet else {

      return (model, target, nil)

    }

    guard let command = commands.standardCommand(named: name), DeviceSettingSafety.isSendable(command, in: commands) else {

      throw DeviceControlError.unsupported(operation, product: model.product)

    }

    return (model, target, command)

  }

  /// A standard command's cmd1 and cmd2: its fixed cmd2, or else `value`.
  static func command(_ command: DeviceStandardCommand, value: UInt8) throws -> Command {

    switch command.command2 {
    case .fixed:
      return try command.command()
    case .parameter:
      return try command.command(.unnamed(Int(value)))
    }

  }

  /// Sends Light Status Request and returns its reply as a raw byte. Nothing says the byte is
  /// the device's level, so only when the device answered is recorded.
  func rawStatus(group: Int?) async throws -> DeviceStatus {

    let acknowledgment: ReceivedMessage = try await request(
      StandardMessage(to: address, command: StandardDirectCommand.statusRequest()),
      timeout: network.requestTimeout,
      for: .control(.status)
    )
    let value: UInt8 = acknowledgment.command.command2

    await network.recordAnswer(of: address, level: nil)

    return DeviceStatus(group: group, value: value, allLinkDatabaseDelta: acknowledgment.command.command1, reading: .raw, isOn: value != 0)

  }

  /// Reads a group's state from the byte its state command's acknowledgment carried.
  ///
  /// - Parameters:
  ///   - value: The byte.
  ///   - group: The group.
  ///   - model: The device's model.
  ///   - reply: What the command set says the acknowledgment carries, if anything.
  /// - Returns: For a state whose catalog entry gives the bits that mean on, whether they match;
  ///   for a state with a bit per group, the group's bit as on or off; for a group that
  ///   dims, whose reply is in percent, the level in percent; the name of the range the value
  ///   is in; on or off for a group that only turns on and off; and otherwise the raw byte.
  static func reading(
    of value: UInt8,
    group: DeviceControlModel.Group,
    in model: DeviceControlModel,
    reply: MessageField?
  ) -> (reading: DeviceStatus.Reading, isOn: Bool) {

    let isNonzero: Bool = value != 0

    guard let state = group.type.state else {

      return (.raw, isNonzero)

    }

    // A reply whose bits carry more than the group's state, such as an EZFlora's valve status,
    // is on only when the bits the catalog names match.
    if let onWhen = state.onWhen {

      let isOn: Bool = onWhen.isOn(command2: value)

      return (.onOff(isOn), isOn)

    }

    if state.isBitPerGroup {

      let number: Int = Int(group.number.rawValue)

      guard (1...8).contains(number) else {

        return (.raw, isNonzero)

      }

      let isOn: Bool = ((value >> UInt8(number - 1)) & 0x01) == 0x01

      return (.onOff(isOn), isOn)

    }

    // A catalog's scale can make the number NaN or infinite, which can't become an `Int`, so
    // it's clamped as a `Double` first.
    if model.canDim(group), let reply, case let .number(_, _, unit) = reply.kind, unit == .percent, case let .number(number)? = reply.value(command2: value, userData: nil), !number.isNaN {

      let percent: Int = Int(min(max(number.rounded(), 0), 100))

      return (.percent(percent), isNonzero)

    }

    if let range = state.ranges.first(where: { (range: GroupType.State.Range) -> Bool in range.values.contains(value) }) {

      return (.named(range.label), isNonzero)

    }

    if model.turnsOnAndOff(group) {

      return (.onOff(isNonzero), isNonzero)

    }

    return (.raw, isNonzero)

  }

  /// The device's description and command set, for its settings.
  func describedSettings() async throws -> (DeviceDescription, CommandSet) {

    guard let description = try await deviceDescription() else {

      throw DeviceSettingError.notIdentified

    }

    guard let commands = description.commandSet else {

      throw DeviceSettingError.noSettings(product: DeviceControlModel.product(of: description))

    }

    return (description, commands)

  }

  /// The device's acknowledgment, or `nil` if it rejected the message or didn't answer.
  func answer(_ message: StandardMessage) async throws -> ReceivedMessage? {

    do {

      return try await request(message, timeout: network.requestTimeout, for: .control(.settings))

    } catch let error as ModemError {

      switch error {
      case .deviceRejected, .deviceTimedOut:
        return nil
      default:
        throw error
      }

    }

  }

  /// The values of an extended Get's reply for a button, or `nil` if the device rejected the
  /// Get or didn't reply.
  func readValues(settings: ExtendedSettings, button: UInt8) async throws -> [SettingName: UInt8]? {

    let device: InsteonAddress = address
    let modem: any LinkingModem = self.modem
    let message = ExtendedMessage(to: device, command: ExtendedDirectCommand.getSet(), userData: settings.getUserData(button: button))
    let isPerButton: Bool = settings.isPerButton

    try await refuseIfNeverSent(message.command, userData: message.userData, for: .control(.settings))

    do {

      return try await modem.firstReply(
        within: Modem.defaultExtendedRequestTimeout,
        clock: network.clock,
        after: { () async throws -> Void in

          _ = try await modem.request(message, timeout: Modem.defaultExtendedRequestTimeout)

        },
        matching: { (reply: ModemReply) -> [SettingName: UInt8]? in

          guard case let .messageReceived(received) = reply, received.sender == device else {

            return nil

          }

          // A device whose values are per button says in D1 which button they're for.
          if isPerButton, received.userData?[1] != button {

            return nil

          }

          return settings.values(in: received)

        }
      )

    } catch let error as ModemError {

      switch error {
      case .deviceRejected, .deviceTimedOut:
        return nil
      default:
        throw error
      }

    }

  }

  /// The Get Operating Flags requests the items need, each once, in order.
  static func queries(of items: [SettingItem]) -> [OperatingFlagsRequest] {

    var queries: [OperatingFlagsRequest] = []

    for item in items {

      let query: OperatingFlagsRequest?

      switch item.source {
      case let .flag(flag):
        query = flag.query
      case let .reading(reading):
        query = reading.query
      case .value:
        query = nil
      }

      if let query, !queries.contains(query) {

        queries.append(query)

      }

    }

    return queries

  }

  /// Whether an item is an extended settings value.
  static func isValue(_ item: SettingItem) -> Bool {

    if case .value = item.source {

      return true

    }

    return false

  }

  /// Button 1, then, when some of the items are values per button, the device's other groups,
  /// leaving out group 255.
  static func buttons(for items: [SettingItem], in commands: CommandSet, description: DeviceDescription) -> [UInt8] {

    guard
      let settings = commands.extendedSettings,
      settings.isPerButton,
      items.contains(where: { (item: SettingItem) -> Bool in settings.isValuePerButton(item.name) && Self.isValue(item) }),
      let profile = description.profile
    else {

      return [0x01]

    }

    let others: [UInt8] = profile.groups
      .map { (group: DeviceProfile.Group) -> UInt8 in group.number.rawValue }
      .filter { (number: UInt8) -> Bool in number > 1 && number < 0xFF }

    return [0x01] + Array(Set(others)).sorted()

  }

}
