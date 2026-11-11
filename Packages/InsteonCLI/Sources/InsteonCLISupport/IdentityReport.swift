import InsteonCore

/// What `insteon device ADDRESS id` learned about a device: its ID Request's answer, its
/// Product Data when it was asked, and what the Insteon device catalog says about it.
public struct IdentityReport: Hashable, Sendable {

  /// The device.
  public var device: InsteonAddress

  /// The device's engine, or `nil` if it isn't known.
  public var engine: InsteonEngine?

  /// Whether the device takes commands from the modem.
  public var acceptsModem: Bool

  /// The device's category: from the identity it reported, else from its Product Data.
  public var category: DeviceCategory?

  /// The device's subcategory: from the identity it reported, else from its Product Data.
  public var subcategory: DeviceSubcategory?

  /// The firmware version the identity reported, or `nil`.
  public var firmwareVersion: FirmwareVersion?

  /// The device's answer to Product Data Request, or `nil` if it wasn't asked or didn't
  /// answer.
  public var productData: DeviceProductData?

  /// The product the catalog names, or `nil`.
  public var product: String?

  /// What the catalog says the product reports as its key, or `nil`.
  public var catalogKey: ExpectedProductKey?

  /// Whether a device was seen reporting the catalog's key.
  public var isCatalogKeyObserved: Bool

  /// A device's answer to ID Request.
  public struct Answer: Hashable, Sendable {

    /// The device's engine, or `nil` if it isn't known.
    public var engine: InsteonEngine?

    /// Whether the device takes commands from the modem.
    public var acceptsModem: Bool

    /// The category the device reported, or `nil` if it reported no identity.
    public var category: DeviceCategory?

    /// The subcategory the device reported, or `nil`.
    public var subcategory: DeviceSubcategory?

    /// The firmware version the device reported, or `nil`.
    public var firmwareVersion: FirmwareVersion?

    /// Creates an answer.
    ///
    /// - Parameters:
    ///   - engine: The device's engine.
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

  /// Asks a device what it is: ID Request, then Product Data Request only when the device
  /// takes the modem's commands, since an i2CS device that isn't linked ignores it. The
  /// category and subcategory come from the identity, else from the Product Data.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - identify: Sends ID Request, as `DeviceNetwork.identify(_:)` does.
  ///   - productData: Sends Product Data Request, as `DeviceNetwork.productData(of:)` does,
  ///     returning `nil` when the device doesn't answer.
  ///   - catalogInfo: What the catalog says about the device once it's identified.
  ///   - productName: The product the catalog names for an identity.
  /// - Returns: The report.
  /// - Throws: What the requests throw.
  public static func read(
    _ device: InsteonAddress,
    identify: () async throws -> Answer,
    productData: () async throws -> DeviceProductData?,
    catalogInfo: () async -> DeviceInfo?,
    productName: (DeviceCategory, DeviceSubcategory, FirmwareVersion?) -> String?
  ) async throws -> IdentityReport {

    let answer: Answer = try await identify()
    let data: DeviceProductData? = answer.acceptsModem ? try await productData() : nil
    let category: DeviceCategory? = answer.category ?? data?.category
    let subcategory: DeviceSubcategory? = answer.subcategory ?? data?.subcategory
    var product: String?

    if let category, let subcategory {

      product = productName(category, subcategory, answer.firmwareVersion)

    }

    // What the catalog says the product reports explains a key that's missing.
    let info: DeviceInfo? = await catalogInfo()

    return IdentityReport(
      device: device,
      engine: answer.engine,
      acceptsModem: answer.acceptsModem,
      category: category,
      subcategory: subcategory,
      firmwareVersion: answer.firmwareVersion,
      productData: data,
      product: product,
      catalogKey: info?.expectedProductKey,
      isCatalogKeyObserved: info?.isExpectedProductKeyObserved == true
    )

  }

}

extension IdentityText {

  /// The rows `insteon device ADDRESS id` prints. The product row needs an identity and a
  /// catalog.
  ///
  /// - Parameters:
  ///   - report: What the device reported.
  ///   - namesProducts: Whether the command has a catalog.
  /// - Returns: The rows.
  public static func rows(_ report: IdentityReport, namesProducts: Bool) -> [[String]] {

    let categoryText: String = report.category.map(Names.category) ?? "not reported"
    let subcategoryText: String = report.subcategory.map { "\($0)" } ?? "not reported"
    let firmwareText: String = report.firmwareVersion.map { "\($0)" } ?? "not reported"
    // Newer devices leave the product key out, or report zeros; that's expected, not a failure.
    let productKeyText: String = productKey(
      reported: report.productData?.productKey,
      answered: report.productData != nil,
      catalog: report.catalogKey,
      isCatalogKeyObserved: report.isCatalogKeyObserved
    )
    var rows: [[String]] = [
      ["Device:", "\(report.device)"],
      ["Engine:", Names.engine(report.engine)],
      ["Category:", categoryText],
      ["Subcategory:", subcategoryText],
      ["Firmware:", firmwareText],
      ["Product key:", productKeyText]
    ]

    // Without an identity, or without the catalog, nothing is said about the product.
    if report.category != nil, namesProducts {

      rows.append(["Product:", report.product ?? "not in the Insteon device catalog"])

    }

    return rows

  }

  /// A device's identity as `insteon device ADDRESS id --json` prints it. A value that isn't
  /// known is left out.
  public struct JSON: Encodable, Hashable, Sendable {

    /// The device's address.
    public let address: String

    /// The engine's name, or `"unknown"`.
    public let engine: String

    /// Whether the device takes commands from the modem.
    public let acceptsModem: Bool

    /// The category, such as `"0x01"`.
    public let category: String?

    /// The category's name.
    public let categoryName: String?

    /// The subcategory.
    public let subcategory: String?

    /// The firmware version.
    public let firmwareVersion: String?

    /// The product key the device reported.
    public let productKey: String?

    /// The product key the Insteon device catalog gives, or `"none"` for a product it says
    /// reports none.
    public let catalogProductKey: String?

    /// The product the catalog names.
    public let product: String?

    /// The JSON for a report.
    ///
    /// - Parameter report: What the device reported.
    public init(_ report: IdentityReport) {

      address = "\(report.device)"
      engine = Names.engine(report.engine)
      acceptsModem = report.acceptsModem
      category = report.category.map { "\($0)" }
      categoryName = report.category?.name
      subcategory = report.subcategory.map { "\($0)" }
      firmwareVersion = report.firmwareVersion.map { "\($0)" }
      productKey = report.productData?.productKey.map { "\($0)" }
      catalogProductKey = IdentityText.catalogProductKey(report.catalogKey)
      product = report.product

    }

  }

}
