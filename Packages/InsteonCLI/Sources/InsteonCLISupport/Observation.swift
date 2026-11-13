import Foundation

/// How a device took one request of an observation.
public enum ObservationOutcome: String, Codable, Hashable, Sendable {

  /// The device acknowledged the request or sent what it asks for.
  case answered

  /// The device sent nothing back, which a device that is asleep also does.
  case silent

  /// The device refused the request.
  case refused

}

/// One request of an observation and how the device took it.
public struct ObservationCheckResult: Hashable, Sendable {

  /// What was asked, such as `"ID Request"`.
  public var name: String

  /// How the device took it.
  public var outcome: ObservationOutcome

  /// A short plain sentence about the result.
  public var detail: String

  /// Creates a result.
  ///
  /// - Parameters:
  ///   - name: What was asked.
  ///   - outcome: How the device took it.
  ///   - detail: A short plain sentence about the result.
  public init(name: String, outcome: ObservationOutcome, detail: String) {

    self.name = name
    self.outcome = outcome
    self.detail = detail

  }

}

/// What the checks of an observation found out about a device.
///
/// It holds nothing that names the home: no device, modem or Hub address, and no account.
public struct ObservationFindings: Hashable, Sendable {

  /// The engine the device reported, such as `"i2CS"`, or `nil`.
  public var engine: String?

  /// The category the device reported, such as `"0x01"`, or `nil`.
  public var category: String?

  /// The subcategory the device reported, or `nil`.
  public var subcategory: String?

  /// The firmware version the device reported, or `nil`.
  public var firmware: String?

  /// The product the Insteon device catalog names for the device, or `nil` if it names none.
  public var model: String?

  /// The product key the device reported, such as `"0x00001A"`; `"none"` if it answered Product
  /// Data Request and reported no key; `nil` if the request got no answer, was refused or
  /// wasn't made. The file leaves the key out for `nil`.
  public var productKey: String?

  /// The bytes the device gave for its operating flags, or `nil` if it gave none.
  public var operatingFlags: [UInt8]?

  /// The requests made, in order.
  public var checks: [ObservationCheckResult]

  /// Creates findings.
  ///
  /// - Parameters:
  ///   - engine: The engine the device reported.
  ///   - category: The category the device reported.
  ///   - subcategory: The subcategory the device reported.
  ///   - firmware: The firmware version the device reported.
  ///   - model: The product the catalog names for the device.
  ///   - productKey: The product key the device reported.
  ///   - operatingFlags: The bytes the device gave for its operating flags.
  ///   - checks: The requests made, in order.
  public init(
    engine: String?,
    category: String?,
    subcategory: String?,
    firmware: String?,
    model: String?,
    productKey: String?,
    operatingFlags: [UInt8]?,
    checks: [ObservationCheckResult]
  ) {

    self.engine = engine
    self.category = category
    self.subcategory = subcategory
    self.firmware = firmware
    self.model = model
    self.productKey = productKey
    self.operatingFlags = operatingFlags
    self.checks = checks

  }

}

/// The program that made an observation.
public struct ObservationTool: Hashable, Sendable {

  /// The program's name.
  public var name: String

  /// The program's version.
  public var version: String

  /// Creates a tool.
  ///
  /// - Parameters:
  ///   - name: The program's name.
  ///   - version: The program's version.
  public init(name: String, version: String) {

    self.name = name
    self.version = version

  }

}

/// Why an observation can't be written.
public enum ObservationError: Error, Hashable, Sendable, CustomStringConvertible {

  /// The note holds something that looks like an address or a host name.
  case noteHoldsAddress

  public var description: String {

    switch self {
    case .noteHoldsAddress:
      "The note looks like it holds an address or a host name. Take it out, so the file says nothing about your home."
    }

  }

}

/// What `insteon observe` writes: a small JSON file that records what a device did, for a
/// person to attach to an issue or a pull request.
///
/// The file holds no address of a device, the modem or a Hub, no host and no account data. It
/// is built from ``ObservationFindings``, which has no place for any of them, and the text in
/// its checks is stripped of anything that looks like one. A request the device didn't answer
/// is recorded as silent and says the device may need to be awake; the file never states
/// the silence as a fact about the device.
///
/// The format is described by `Schemas/insteon-observation-1.schema.json` in the InsteonCLI
/// package.
public struct Observation: Encodable, Hashable, Sendable {

  /// The format's name and version, as the file's `format` holds it.
  public static let format: String = "insteon-observation/1"

  /// What a silent check says besides its detail.
  static let awakeSentence: String = "It may need to be awake."

  /// The product key the file holds for a device that answered Product Data Request and
  /// reported no key.
  static let noKey: String = "none"

  /// The program that made the observation.
  public let tool: ObservationTool

  /// The version of the Insteon device catalog used to name the device.
  public let catalogVersion: String

  /// What the device reported.
  public let findings: ObservationFindings

  /// The person's note, or `nil`.
  public let note: String?

  /// The day of the observation, as `YYYY-MM-DD` in the calendar's time zone.
  public let observedOn: String

  /// Builds the file from what the checks found.
  ///
  /// - Parameters:
  ///   - findings: What the checks found.
  ///   - tool: The program that ran them.
  ///   - catalogVersion: The version of the catalog that named the device.
  ///   - note: The person's note, or `nil`.
  ///   - observedOn: The moment of the observation; only its date is kept.
  ///   - calendar: The calendar, and so the time zone, whose date is kept. Defaults to the
  ///     current calendar.
  /// - Throws: ``ObservationError/noteHoldsAddress`` if the note looks like it holds an
  ///   address or a host name.
  public init(
    _ findings: ObservationFindings,
    tool: ObservationTool,
    catalogVersion: String,
    note: String?,
    observedOn: Date,
    calendar: Calendar = .current
  ) throws(ObservationError) {

    if let note, ObservationRedaction.strip(note) != note {

      throw ObservationError.noteHoldsAddress

    }

    var clean = findings

    clean.checks = findings.checks.map { (check: ObservationCheckResult) -> ObservationCheckResult in

      var detail: String = ObservationRedaction.strip(check.detail)

      if check.outcome == .silent, !detail.lowercased().contains("awake") {

        detail = detail.isEmpty ? Self.awakeSentence : "\(detail) \(Self.awakeSentence)"

      }

      return ObservationCheckResult(name: ObservationRedaction.strip(check.name), outcome: check.outcome, detail: detail)

    }

    let parts: DateComponents = calendar.dateComponents([.year, .month, .day], from: observedOn)

    self.tool = tool
    self.catalogVersion = catalogVersion
    self.findings = clean
    self.note = note
    self.observedOn = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)

  }

  /// The file's JSON: pretty-printed, with sorted keys.
  ///
  /// - Returns: The JSON, ending with a newline.
  /// - Throws: An encoding error, which doesn't happen for these values.
  public func json() throws -> Data {

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    return try encoder.encode(self) + Data("\n".utf8)

  }

  private enum CodingKeys: String, CodingKey {

    case format, tool, catalog, device, checks, productKey, operatingFlags, note, observedOn

  }

  private enum DeviceKeys: String, CodingKey {

    case category, subcategory, firmware, engine, model

  }

  private enum CheckKeys: String, CodingKey {

    case name, outcome, detail

  }

  private enum RawKeys: String, CodingKey {

    case raw

  }

  public func encode(to encoder: any Encoder) throws {

    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encode(Self.format, forKey: .format)

    var toolContainer = container.nestedContainer(keyedBy: ToolKeys.self, forKey: .tool)

    try toolContainer.encode(tool.name, forKey: .name)
    try toolContainer.encode(tool.version, forKey: .version)

    var catalogContainer = container.nestedContainer(keyedBy: ToolKeys.self, forKey: .catalog)

    try catalogContainer.encode(catalogVersion, forKey: .version)

    // Optional values are encoded as null, so the file always has every device key.
    var device = container.nestedContainer(keyedBy: DeviceKeys.self, forKey: .device)

    try device.encode(findings.category, forKey: .category)
    try device.encode(findings.subcategory, forKey: .subcategory)
    try device.encode(findings.firmware, forKey: .firmware)
    try device.encode(findings.engine, forKey: .engine)
    try device.encode(findings.model, forKey: .model)

    var checks = container.nestedUnkeyedContainer(forKey: .checks)

    for check in findings.checks {

      var each = checks.nestedContainer(keyedBy: CheckKeys.self)

      try each.encode(check.name, forKey: .name)
      try each.encode(check.outcome, forKey: .outcome)
      try each.encode(check.detail, forKey: .detail)

    }

    try container.encodeIfPresent(findings.productKey, forKey: .productKey)

    if let bytes = findings.operatingFlags, !bytes.isEmpty {

      var flags = container.nestedContainer(keyedBy: RawKeys.self, forKey: .operatingFlags)

      try flags.encode(bytes.map { (byte: UInt8) -> String in String(format: "%02X", byte) }.joined(separator: " "), forKey: .raw)

    }

    try container.encodeIfPresent(note, forKey: .note)
    try container.encode(observedOn, forKey: .observedOn)

  }

  private enum ToolKeys: String, CodingKey {

    case name, version

  }

}

/// Takes from text what names a home: a device, modem or Hub address, an IP address, a host
/// name, a URL, an account name and an e-mail address.
public enum ObservationRedaction {

  /// What replaces each thing taken out.
  public static let placeholder: String = "[removed]"

  private static let patterns: [String] = [
    // A URL, and an e-mail address.
    #"[A-Za-z][A-Za-z0-9+.-]*://\S+"#,
    #"[^\s@]+@[^\s@]+"#,
    // A hardware address of six pairs, then an Insteon address of three, with any separator.
    #"\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"#,
    #"\b[0-9A-Fa-f]{2}[.:-][0-9A-Fa-f]{2}[.:-][0-9A-Fa-f]{2}\b"#,
    // An IPv4 address, with or without a port.
    #"\b\d{1,3}(?:\.\d{1,3}){3}(?::\d{1,5})?\b"#,
    // A host name, with or without a port.
    #"\b[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}(?::\d{1,5})?\b"#,
    // An Insteon address without separators; a product key (0x00001A) never matches, since
    // its digits follow the x without a word boundary.
    #"\b(?=[0-9A-Fa-f]*\d)[0-9A-Fa-f]{6}\b"#
  ]

  /// The text with each address, host and account name replaced by ``placeholder``.
  ///
  /// - Parameter text: The text.
  /// - Returns: The text, unchanged if it names nothing.
  public static func strip(_ text: String) -> String {

    var result: String = text

    for pattern in patterns {

      guard let expression = try? NSRegularExpression(pattern: pattern) else {

        continue

      }

      let range = NSRange(result.startIndex..., in: result)

      result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: placeholder))

    }

    return result

  }

}
