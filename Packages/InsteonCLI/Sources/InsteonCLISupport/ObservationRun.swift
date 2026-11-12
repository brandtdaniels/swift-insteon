import InsteonCore

/// How a device took a request: it answered with a value, sent nothing back, or refused.
public enum ObservationReply<Value> {

  /// The device answered.
  case answered(Value)

  /// The device sent nothing back, as a device that is asleep also does.
  case silent

  /// The device refused the request.
  case refused

  /// Reads how a device took a request from what the request threw.
  ///
  /// - Parameters:
  ///   - failure: What the error says went wrong, or `nil` if it isn't a send failure.
  ///   - error: The error, thrown again when it isn't about the device.
  /// - Returns: ``silent`` for a device that didn't answer, and ``refused`` for one that
  ///   rejected the request.
  /// - Throws: `error`, when the modem or the connection failed, or the task was canceled.
  public static func classify(_ failure: SendFailure?, error: any Error) throws -> ObservationReply<Value> {

    switch failure {
    case .deviceUnanswered?:
      return .silent
    case .deviceRejected?:
      return .refused
    case .modemRejected?, .modemUnanswered?, nil:
      throw error
    }

  }

  /// Reads how a device took a request from the error it threw.
  ///
  /// - Parameter error: The error.
  /// - Returns: ``silent`` or ``refused``.
  /// - Throws: `error`, when it isn't about the device.
  public static func classify(_ error: any Error) throws -> ObservationReply<Value> {

    try classify(SendFailure(error), error: error)

  }

}

extension ObservationReply: Equatable where Value: Equatable {}

extension ObservationReply: Sendable where Value: Sendable {}

/// What a device reported to Get Insteon Engine Version and ID Request.
public struct ObservedIdentity: Hashable, Sendable {

  /// The engine, or `nil` if the device gave a value that isn't one.
  public var engine: InsteonEngine?

  /// Whether the device takes commands from the modem.
  public var acceptsModem: Bool

  /// The category the device reported, or `nil` if it reported no identity.
  public var category: DeviceCategory?

  /// The subcategory the device reported.
  public var subcategory: DeviceSubcategory?

  /// The firmware version the device reported.
  public var firmwareVersion: FirmwareVersion?

  /// Creates what a device reported.
  ///
  /// - Parameters:
  ///   - engine: The engine.
  ///   - acceptsModem: Whether the device takes commands from the modem.
  ///   - category: The category it reported.
  ///   - subcategory: The subcategory it reported.
  ///   - firmwareVersion: The firmware version it reported.
  public init(
    engine: InsteonEngine?,
    acceptsModem: Bool,
    category: DeviceCategory? = nil,
    subcategory: DeviceSubcategory? = nil,
    firmwareVersion: FirmwareVersion? = nil
  ) {

    self.engine = engine
    self.acceptsModem = acceptsModem
    self.category = category
    self.subcategory = subcategory
    self.firmwareVersion = firmwareVersion

  }

}

/// The device `insteon observe` asks, and the catalog that names it. Every request is a read.
public protocol ObservationSource {

  /// Sends Get Insteon Engine Version, then ID Request.
  func identify() async throws -> ObservationReply<ObservedIdentity>

  /// Sends Product Data Request.
  func productData() async throws -> ObservationReply<DeviceProductData>

  /// The product the Insteon device catalog names for an identity, or `nil`.
  func productName(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> String?

  /// Reads the device's state with the request the catalog gives for it.
  ///
  /// - Returns: How the device took it, or `nil` if the catalog gives no such request.
  func readStatus() async throws -> ObservationReply<Void>?

  /// Reads the device's operating flags with the requests the catalog gives for them.
  ///
  /// - Returns: How the device took them, with the bytes it gave, or `nil` if the catalog
  ///   gives no such request.
  func readOperatingFlags() async throws -> ObservationReply<[UInt8]>?

}

/// Asks a device what it is and how it answers, with requests that only read.
public enum ObservationRun {

  /// The names the checks go by.
  enum Name {

    static let engine = "Get Insteon Engine Version"
    static let identity = "ID Request"
    static let productData = "Product Data Request"
    static let status = "Status Request"
    static let operatingFlags = "Get Operating Flags"

  }

  /// Asks the device for its engine and identity, its product data, its state and its operating
  /// flags, in that order, and records how it took each.
  ///
  /// A device that answers neither of the first two requests is asked nothing more, since a
  /// device that is asleep answers none. A request after them that the device doesn't answer
  /// is recorded, and the next is still asked.
  ///
  /// - Parameter source: The device to ask.
  /// - Returns: What the device reported, and how it took each request.
  /// - Throws: `DeviceControlError.notLinked` if the device rejects the modem as not linked
  ///   to it, and the errors of the modem and the connection.
  public static func observe(_ source: some ObservationSource) async throws -> ObservationFindings {

    var checks: [ObservationCheckResult] = []

    let identity: ObservedIdentity

    switch try await source.identify() {
    case let .answered(reported):
      identity = reported
    case .silent:
      return ObservationFindings(engine: nil, category: nil, subcategory: nil, firmware: nil, model: nil, productKey: nil, operatingFlags: nil, checks: unanswered(.silent))
    case .refused:
      return ObservationFindings(engine: nil, category: nil, subcategory: nil, firmware: nil, model: nil, productKey: nil, operatingFlags: nil, checks: unanswered(.refused))
    }

    guard identity.acceptsModem else {

      throw DeviceControlError.notLinked

    }

    checks.append(ObservationCheckResult(
      name: Name.engine,
      outcome: .answered,
      detail: identity.engine == nil ? "The device answered with an engine version this command doesn't know." : "The device reported its engine version."
    ))
    checks.append(
      identity.category == nil
        ? ObservationCheckResult(name: Name.identity, outcome: .silent, detail: "No identity followed ID Request.")
        : ObservationCheckResult(name: Name.identity, outcome: .answered, detail: "The device reported its identity.")
    )

    var category: DeviceCategory? = identity.category
    var subcategory: DeviceSubcategory? = identity.subcategory
    var productKey: String?

    switch try await source.productData() {
    case let .answered(data):
      category = category ?? data.category
      subcategory = subcategory ?? data.subcategory
      productKey = data.productKey.map { (key: ProductKey) -> String in "\(key)" }
      checks.append(ObservationCheckResult(
        name: Name.productData,
        outcome: .answered,
        detail: productKey == nil ? "The device answered and reported no product key." : "The device reported a product key."
      ))
    case .silent:
      checks.append(ObservationCheckResult(name: Name.productData, outcome: .silent, detail: "No answer."))
    case .refused:
      checks.append(ObservationCheckResult(name: Name.productData, outcome: .refused, detail: "The device refused the request."))
    }

    if let status = try await source.readStatus() {

      checks.append(result(Name.status, status, answered: "The device reported its state."))

    }

    var flags: [UInt8]?

    if let reply = try await source.readOperatingFlags() {

      checks.append(result(Name.operatingFlags, reply, answered: "The device reported its operating flags."))

      if case let .answered(bytes) = reply {

        flags = bytes

      }

    }

    var model: String?

    if let category, let subcategory {

      model = source.productName(category: category, subcategory: subcategory, firmwareVersion: identity.firmwareVersion)

    }

    return ObservationFindings(
      engine: identity.engine?.name,
      category: category.map { (value: DeviceCategory) -> String in "\(value)" },
      subcategory: subcategory.map { (value: DeviceSubcategory) -> String in "\(value)" },
      firmware: identity.firmwareVersion.map { (value: FirmwareVersion) -> String in "\(value)" },
      model: model,
      productKey: productKey,
      operatingFlags: flags,
      checks: checks
    )

  }

  /// The two checks of a device that took neither of the first requests.
  private static func unanswered(_ outcome: ObservationOutcome) -> [ObservationCheckResult] {

    let detail: String = outcome == .silent
      ? "No answer to Get Insteon Engine Version, or none to ID Request after it. Nothing more was asked."
      : "Get Insteon Engine Version, or ID Request after it, was refused. Nothing more was asked."

    return [
      ObservationCheckResult(name: Name.engine, outcome: outcome, detail: detail),
      ObservationCheckResult(name: Name.identity, outcome: outcome, detail: detail)
    ]

  }

  private static func result<Value>(_ name: String, _ reply: ObservationReply<Value>, answered: String) -> ObservationCheckResult {

    switch reply {
    case .answered:
      ObservationCheckResult(name: name, outcome: .answered, detail: answered)
    case .silent:
      ObservationCheckResult(name: name, outcome: .silent, detail: "No answer.")
    case .refused:
      ObservationCheckResult(name: name, outcome: .refused, detail: "The device refused the request.")
    }

  }

}
