import InsteonProtocol

extension DeviceLifecycle {

  /// Linking a product to a Hub or modem as data an app can follow on its own: the links to
  /// make, in order, who starts, whether the modem can put the device in linking mode, and how
  /// to keep a battery-powered device awake.
  ///
  /// The linking procedure's From a Hub alternative gives the same as steps a person reads.
  /// Removing the product from the Hub undoes each leg.
  ///
  /// ```swift
  /// guard let fromHub = profile.lifecycle?.fromHub else {
  ///   return
  /// }
  ///
  /// for leg in fromHub.legs {
  ///   print(leg.modemRole, leg.modemGroup, leg.deviceGroup)
  /// }
  /// ```
  public struct HubLinking: Hashable, Sendable {

    /// The modem's role in a link.
    public struct Role: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

      /// The role as the catalog writes it, such as `"controller"`.
      public let rawValue: String

      /// Creates a role from the catalog's name for it.
      ///
      /// - Parameter rawValue: The role as the catalog writes it.
      public init(rawValue: String) {

        self.rawValue = rawValue

      }

      /// The modem is the controller, so the Hub can control the device: Start ALL-Linking with
      /// link code `0x01`.
      public static let controller = Role(rawValue: "controller")

      /// The modem is the responder, so the Hub hears the device's group: Start ALL-Linking
      /// with link code `0x00`.
      public static let responder = Role(rawValue: "responder")

      /// The role as the catalog writes it.
      public var description: String { rawValue }

    }

    /// Whether something works, as far as the catalog knows.
    public struct Answer: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

      /// The answer as the catalog writes it, such as `"yes"`.
      public let rawValue: String

      /// Creates an answer from the catalog's name for it.
      ///
      /// - Parameter rawValue: The answer as the catalog writes it.
      public init(rawValue: String) {

        self.rawValue = rawValue

      }

      /// It works.
      public static let yes = Answer(rawValue: "yes")

      /// It doesn't work.
      public static let no = Answer(rawValue: "no")

      /// The catalog can't say.
      public static let unknown = Answer(rawValue: "unknown")

      /// The answer as the catalog writes it.
      public var description: String { rawValue }

    }

    /// One link between the modem and the device, made in one ALL-Linking session.
    ///
    /// The modem starts ALL-Linking first, with the link code for its
    /// ``DeviceLifecycle/HubLinking/Leg/modemRole``, and the device then goes into linking
    /// mode, from its SET button or from Enter Linking Mode. The app waits for ALL-Linking
    /// Completed (`0x53`) before starting the next leg.
    public struct Leg: Hashable, Sendable {

      /// The modem's role in the link.
      public var modemRole: Role

      /// The ALL-Link group Start ALL-Linking names, which the modem's record holds.
      public var modemGroup: AllLinkGroupNumber

      /// The device's group for the link, one of the profile's groups, which Enter Linking
      /// Mode names in cmd2. With the modem as controller, it's the group whose responder
      /// record the device writes; with the modem as responder, the device controls it.
      public var deviceGroup: AllLinkGroupNumber

      /// The operating flag state under which this one link puts the modem in every group the
      /// device controls, such as a sensor's Link to FF Group option, or `nil` if the leg links
      /// ``DeviceLifecycle/HubLinking/Leg/deviceGroup`` alone.
      public var allGroupsWhen: DeviceProfile.Group.Condition?

      /// How sure the catalog is of the leg: its own verification, or else the
      /// ``DeviceLifecycle/HubLinking/verification`` of the whole.
      public var verification: Verification

      /// Creates a leg.
      ///
      /// - Parameters:
      ///   - modemRole: The modem's role in the link.
      ///   - modemGroup: The ALL-Link group Start ALL-Linking names.
      ///   - deviceGroup: The device's group for the link.
      ///   - allGroupsWhen: The operating flag state under which the link covers every group
      ///     the device controls. Defaults to `nil`.
      ///   - verification: How sure the catalog is of the leg. Defaults to ``Verification/documented``.
      public init(
        modemRole: Role,
        modemGroup: AllLinkGroupNumber,
        deviceGroup: AllLinkGroupNumber,
        allGroupsWhen: DeviceProfile.Group.Condition? = nil,
        verification: Verification = .documented
      ) {

        self.modemRole = modemRole
        self.modemGroup = modemGroup
        self.deviceGroup = deviceGroup
        self.allGroupsWhen = allGroupsWhen
        self.verification = verification

      }

    }

    /// Whether the modem can put the device in linking mode for a leg by sending it Enter
    /// Linking Mode (cmd1 `0x09`) with the leg's ``DeviceLifecycle/HubLinking/Leg/deviceGroup``
    /// in cmd2, in place of a person using its SET button.
    ///
    /// It's sent as a standard message to an i2 device and an extended one with a checksum to
    /// an i2CS device. For ``DeviceLifecycle/HubLinking/Answer/unknown``, an app can ask the
    /// device's engine with Get Insteon Engine Version (cmd1 `0x0D`), since i1 devices don't
    /// support Enter Linking Mode, and otherwise has a person use the device's controls.
    public struct RemoteEnterLinkingMode: Hashable, Sendable {

      /// Whether it works. An answer from a later version of the catalog keeps its name.
      public var works: Answer

      /// How sure the catalog is of the answer.
      public var verification: Verification

      /// Creates an answer for Enter Linking Mode.
      ///
      /// - Parameters:
      ///   - works: Whether it works.
      ///   - verification: How sure the catalog is of the answer. Defaults to ``Verification/documented``.
      public init(works: Answer, verification: Verification = .documented) {

        self.works = works
        self.verification = verification

      }

    }

    /// A direct message the modem sends the device.
    public enum HubMessage: Hashable, Sendable {

      /// A flag, standard or extended command in the command set, by name, which gives its
      /// bytes, its engine handling and its parameters, such as how many seconds to stay awake.
      case command(SettingName)

      /// An operating flag to set or clear with Set Operating Flags.
      case flag(DeviceProfile.Group.Condition)

      /// A message given by its bytes, where no command set entry exists.
      case bytes(RawMessage)

    }

    /// A message given by its bytes.
    public struct RawMessage: Hashable, Sendable {

      /// The message's cmd1 and cmd2.
      public var command: Command

      /// Whether it's an extended message.
      public var isExtended: Bool

      /// An extended message's fixed user data bytes. The rest are `0x00`, apart from its
      /// integrity bytes.
      public var fixedBytes: [FixedUserDataByte]

      /// How an extended message's user data is protected.
      public var integrity: MessageIntegrity

      /// Creates a message from its bytes.
      ///
      /// - Parameters:
      ///   - command: The message's cmd1 and cmd2.
      ///   - isExtended: Whether it's an extended message. Defaults to `false`.
      ///   - fixedBytes: An extended message's fixed user data bytes. Defaults to none.
      ///   - integrity: How an extended message's user data is protected. Defaults to
      ///     ``MessageIntegrity/unprotected``.
      public init(command: Command, isExtended: Bool = false, fixedBytes: [FixedUserDataByte] = [], integrity: MessageIntegrity = .unprotected) {

        self.command = command
        self.isExtended = isExtended
        self.fixedBytes = fixedBytes
        self.integrity = integrity

      }

    }

    /// How the modem keeps a battery-powered device awake while it links, so the device hears
    /// the rest of the session.
    public struct KeepAwake: Hashable, Sendable {

      /// When to send the message that keeps the device awake.
      public struct Timing: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

        /// The timing as the catalog writes it, such as `"afterLinked"`.
        public let rawValue: String

        /// Creates a timing from the catalog's name for it.
        ///
        /// - Parameter rawValue: The timing as the catalog writes it.
        public init(rawValue: String) {

          self.rawValue = rawValue

        }

        /// Once a person has woken the device and before it goes into linking mode, which
        /// needs the device's Insteon ID beforehand, such as from its label or an earlier link.
        public static let beforeLinking = Timing(rawValue: "beforeLinking")

        /// Right after ALL-Linking Completed (`0x53`) gives the device's ID, while it's still
        /// awake.
        public static let afterLinked = Timing(rawValue: "afterLinked")

        /// The timing as the catalog writes it.
        public var description: String { rawValue }

      }

      /// When to send ``DeviceLifecycle/HubLinking/KeepAwake/send``. A timing from a later
      /// version of the catalog keeps its name.
      public var timing: Timing

      /// The message that keeps the device awake.
      public var send: HubMessage

      /// The message that lets the device sleep again once linking is done, or `nil` if it
      /// sleeps on its own.
      public var release: HubMessage?

      /// How long ``DeviceLifecycle/HubLinking/KeepAwake/send`` keeps the device awake, when
      /// that's fixed.
      public var duration: Duration?

      /// How sure the catalog is of the messages.
      public var verification: Verification

      /// Creates a way to keep a device awake.
      ///
      /// - Parameters:
      ///   - timing: When to send the message.
      ///   - send: The message that keeps the device awake.
      ///   - release: The message that lets it sleep again. Defaults to `nil`.
      ///   - duration: How long the message keeps it awake. Defaults to `nil`.
      ///   - verification: How sure the catalog is of the messages. Defaults to ``Verification/documented``.
      public init(timing: Timing, send: HubMessage, release: HubMessage? = nil, duration: Duration? = nil, verification: Verification = .documented) {

        self.timing = timing
        self.send = send
        self.release = release
        self.duration = duration
        self.verification = verification

      }

    }

    /// The links to make, in order, one ALL-Linking session each.
    public var legs: [Leg]

    /// Whether a person puts the device in linking mode with its own controls before the modem
    /// starts ALL-Linking for the first leg, as for a battery-powered controller; the first
    /// leg's modem is then the responder. `false` when the modem starts ALL-Linking first for
    /// every leg and the device then joins.
    public var isDeviceFirst: Bool

    /// Whether the modem can put the device in linking mode with Enter Linking Mode, or `nil`
    /// if the catalog doesn't say.
    public var remoteEnterLinkingMode: RemoteEnterLinkingMode?

    /// How to keep a battery-powered device awake while it links, or `nil` if it needn't be,
    /// or the catalog gives the message in a form this package doesn't read.
    public var keepAwake: KeepAwake?

    /// How sure the catalog is of the whole, and of each leg that gives no verification of its
    /// own.
    public var verification: Verification

    /// Creates a way to link a product to a Hub.
    ///
    /// - Parameters:
    ///   - legs: The links to make, in order.
    ///   - isDeviceFirst: Whether a person puts the device in linking mode first. Defaults to
    ///     `false`.
    ///   - remoteEnterLinkingMode: Whether the modem can put the device in linking mode.
    ///     Defaults to `nil`.
    ///   - keepAwake: How to keep a battery-powered device awake. Defaults to `nil`.
    ///   - verification: How sure the catalog is of the whole. Defaults to ``Verification/documented``.
    public init(
      legs: [Leg],
      isDeviceFirst: Bool = false,
      remoteEnterLinkingMode: RemoteEnterLinkingMode? = nil,
      keepAwake: KeepAwake? = nil,
      verification: Verification = .documented
    ) {

      self.legs = legs
      self.isDeviceFirst = isDeviceFirst
      self.remoteEnterLinkingMode = remoteEnterLinkingMode
      self.keepAwake = keepAwake
      self.verification = verification

    }

  }

}

// MARK: - Decodable

extension DeviceLifecycle.HubLinking: Decodable {

  private enum CodingKeys: String, CodingKey {

    case legs
    case deviceFirst
    case remoteEnterLinkingMode
    case keepAwake
    case verification

  }

  private struct ConditionEntry: Decodable {

    let flag: String

    let set: Bool

  }

  private struct LegEntry: Decodable {

    let modem: String

    let modemGroup: ProfileByte

    let deviceGroup: ProfileByte

    let allGroupsWhen: ConditionEntry?

    let verification: Verification?

  }

  private struct RemoteEntry: Decodable {

    let works: String

    let verification: Verification?

  }

  /// A message, or `nil` for one in a form this package doesn't read.
  private struct MessageEntry: Decodable {

    private struct FixedByte: Decodable {

      let position: Int

      let value: ProfileByte

    }

    private enum CodingKeys: String, CodingKey {

      case command
      case flag
      case set
      case command1
      case command2
      case extended
      case data
      case integrity

    }

    let message: DeviceLifecycle.HubLinking.HubMessage?

    init(from decoder: any Decoder) throws {

      let container = try decoder.container(keyedBy: CodingKeys.self)

      if let command = try container.decodeIfPresent(String.self, forKey: .command) {

        message = .command(SettingName(rawValue: command))

        return

      }

      if let flag = try container.decodeIfPresent(String.self, forKey: .flag) {

        message = .flag(DeviceProfile.Group.Condition(flag: SettingName(rawValue: flag), isSet: try container.decode(Bool.self, forKey: .set)))

        return

      }

      guard
        let command1 = try container.decodeIfPresent(ProfileByte.self, forKey: .command1),
        let command2 = try container.decodeIfPresent(ProfileByte.self, forKey: .command2),
        let integrity = MessageIntegrity(rawValue: try container.decodeIfPresent(String.self, forKey: .integrity) ?? MessageIntegrity.unprotected.rawValue)
      else {

        message = nil

        return

      }

      let fixed: [FixedByte] = try container.decodeIfPresent([FixedByte].self, forKey: .data) ?? []

      guard fixed.allSatisfy({ (1...UserData.count).contains($0.position) }) else {

        throw DecodingError.dataCorruptedError(forKey: .data, in: container, debugDescription: "A fixed byte isn't in D1 through D14.")

      }

      message = .bytes(DeviceLifecycle.HubLinking.RawMessage(
        command: Command(command1: command1.value, command2: command2.value),
        isExtended: try container.decodeIfPresent(Bool.self, forKey: .extended) ?? false,
        fixedBytes: fixed.map { FixedUserDataByte(position: $0.position, value: $0.value.value) },
        integrity: integrity
      ))

    }

  }

  private struct KeepAwakeEntry: Decodable {

    private enum CodingKeys: String, CodingKey {

      case when
      case send
      case release
      case seconds
      case verification

    }

    let keepAwake: DeviceLifecycle.HubLinking.KeepAwake?

    init(from decoder: any Decoder) throws {

      let container = try decoder.container(keyedBy: CodingKeys.self)

      guard
        let when = try container.decodeIfPresent(String.self, forKey: .when),
        let send = try container.decodeIfPresent(MessageEntry.self, forKey: .send)?.message
      else {

        keepAwake = nil

        return

      }

      keepAwake = DeviceLifecycle.HubLinking.KeepAwake(
        timing: DeviceLifecycle.HubLinking.KeepAwake.Timing(rawValue: when),
        send: send,
        release: try container.decodeIfPresent(MessageEntry.self, forKey: .release)?.message,
        duration: try container.decodeSecondsIfPresent(forKey: .seconds),
        verification: try container.decodeIfPresent(Verification.self, forKey: .verification) ?? .documented
      )

    }

  }

  /// Decodes a way to link a product to a Hub from a profile's `lifecycle.fromHub`.
  ///
  /// A leg without its own verification takes the whole's. A role, answer or timing from a
  /// later version of the catalog keeps its name. A keep-awake message in a form this package
  /// doesn't read, or without its timing, reads as `nil`, as does a release message in such a
  /// form.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the JSON isn't a way to link a product to a Hub, a byte
  ///   isn't written as `0x` and two hexadecimal digits, a fixed byte isn't in D1 through D14,
  ///   or a number of seconds is negative or longer than a year.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)
    let verification: Verification = try container.decodeIfPresent(Verification.self, forKey: .verification) ?? .documented

    self.init(
      legs: try (container.decodeIfPresent([LegEntry].self, forKey: .legs) ?? []).map { leg in

        Leg(
          modemRole: Role(rawValue: leg.modem),
          modemGroup: AllLinkGroupNumber(rawValue: leg.modemGroup.value),
          deviceGroup: AllLinkGroupNumber(rawValue: leg.deviceGroup.value),
          allGroupsWhen: leg.allGroupsWhen.map { DeviceProfile.Group.Condition(flag: SettingName(rawValue: $0.flag), isSet: $0.set) },
          verification: leg.verification ?? verification
        )

      },
      isDeviceFirst: try container.decodeIfPresent(Bool.self, forKey: .deviceFirst) ?? false,
      remoteEnterLinkingMode: try container.decodeIfPresent(RemoteEntry.self, forKey: .remoteEnterLinkingMode).map { remote in

        RemoteEnterLinkingMode(works: Answer(rawValue: remote.works), verification: remote.verification ?? .documented)

      },
      keepAwake: try container.decodeIfPresent(KeepAwakeEntry.self, forKey: .keepAwake)?.keepAwake,
      verification: verification
    )

  }

}
