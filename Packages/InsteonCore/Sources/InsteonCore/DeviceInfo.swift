import InsteonDeviceCatalog
import InsteonProtocol

/// What the Insteon device catalog says about a device that reported an identity: its
/// product, and how to read what it holds.
///
/// A device the catalog doesn't have still has the identity it reported, with no product.
///
/// ```swift
/// if let lamp = await network.registry.device(InsteonAddress(0x1A, 0x2B, 0x3C)) {
///   print(lamp.info.displayName ?? "\(lamp.info.category)")
/// }
/// ```
public struct DeviceInfo: Hashable, Sendable {

  /// The catalog's description the facts come from.
  let catalogDescription: DeviceDescription

  /// The facts a catalog description gives.
  init(_ description: DeviceDescription) {

    self.catalogDescription = description

  }

  /// The category the device reported.
  public var category: DeviceCategory {

    catalogDescription.category

  }

  /// The subcategory the device reported.
  public var subcategory: DeviceSubcategory {

    catalogDescription.subcategory

  }

  /// The firmware version the device reported, or `nil` if it isn't known.
  public var firmwareVersion: FirmwareVersion? {

    catalogDescription.firmwareVersion

  }

  /// The product's name for a person, such as `"Dimmer Switch 2477D"`, or `nil` if the
  /// catalog doesn't have the device.
  public var displayName: String? {

    catalogDescription.displayName

  }

  /// The product's name, such as `"Dimmer Switch"`, or `nil` if the catalog doesn't have the
  /// device.
  public var productName: String? {

    catalogDescription.profile?.name

  }

  /// The product's model, such as `"2477D"`, or `nil` if the catalog doesn't have the device.
  public var model: String? {

    catalogDescription.profile.map { (profile: DeviceProfile) -> String in "\(profile.model)" }

  }

  /// Whether the catalog has the device's product.
  public var isInCatalog: Bool {

    catalogDescription.profile != nil

  }

  /// The Insteon engine the catalog gives the product, or `nil` if it doesn't say.
  public var engine: InsteonEngine? {

    catalogDescription.engine

  }

  /// The product key the catalog says the product reports, or that it reports none, or `nil`
  /// if the catalog doesn't say.
  public var expectedProductKey: ExpectedProductKey? {

    catalogDescription.productKey.map { (entry: DeviceIdentity.ProductKeyEntry) -> ExpectedProductKey in ExpectedProductKey(entry) }

  }

  /// What a record's data bytes mean for the device, as the catalog gives them.
  ///
  /// A controller record's bytes are read by the group type of the record's group, and a
  /// responder record's by the group type its bytes name.
  ///
  /// - Parameter record: The record, from the device's ALL-Link database.
  /// - Returns: What the bytes mean, or `nil` if the catalog doesn't describe them.
  public func meaning(of record: LinkRecord) -> LinkDataMeaning? {

    catalogDescription.explain(record.allLinkRecord, isController: record.isController).map { (explanation: RecordDataExplanation) -> LinkDataMeaning in

      LinkDataMeaning(explanation)

    }

  }

}

/// The product key the Insteon device catalog gives a product: a key, or that the product
/// reports none.
public enum ExpectedProductKey: Hashable, Sendable {

  /// The product reports this key.
  case key(ProductKey)

  /// The product reports no key, as newer products don't.
  case notReported

  /// The key the catalog's entry gives.
  init(_ entry: DeviceIdentity.ProductKeyEntry) {

    switch entry {
    case let .key(key):
      self = .key(key)
    case .notReported:
      self = .notReported
    }

  }

}

/// What the data bytes of an ALL-Link record mean, as the Insteon device catalog gives them,
/// from ``DeviceInfo/meaning(of:)``.
public struct LinkDataMeaning: Hashable, Sendable {

  /// The bytes the catalog describes, from Data 1 through Data 3.
  public var bytes: [LinkDataField]

  /// Creates a meaning.
  ///
  /// - Parameter bytes: The bytes the catalog describes.
  public init(bytes: [LinkDataField]) {

    self.bytes = bytes

  }

  /// The meaning the catalog's explanation gives.
  init(_ explanation: RecordDataExplanation) {

    self.init(bytes: explanation.bytes.map { (byte: RecordDataExplanation.DataByte) -> LinkDataField in LinkDataField(byte) })

  }

}

/// One data byte of an ALL-Link record, with what it holds.
public struct LinkDataField: Hashable, Sendable {

  /// Which data byte of the record it is, from 1 through 3.
  public var position: Int

  /// The byte's name, such as `"onLevel"`.
  public var name: String

  /// What a settings page calls the byte, such as `"On-level"`, if the catalog says.
  public var label: String?

  /// The byte's value in the record.
  public var value: UInt8

  /// The name of the value, such as a ramp rate's `"0.5 seconds"`, or `nil` if the catalog
  /// doesn't name it.
  public var valueName: String?

  /// Whether the byte is the responder's own group, so the value is a group number.
  public var isPerGroup: Bool

  /// The value the catalog gives for the byte when it's fixed, such as an on-level of
  /// `0xFE`, or `nil` if the byte can take any value.
  public var documentedValue: UInt8?

  /// Creates a byte.
  ///
  /// - Parameters:
  ///   - position: Which data byte of the record it is, from 1 through 3.
  ///   - name: The byte's name.
  ///   - label: What a settings page calls the byte. Defaults to `nil`.
  ///   - value: The byte's value in the record.
  ///   - valueName: The name of the value. Defaults to `nil`.
  ///   - isPerGroup: Whether the byte is the responder's own group. Defaults to `false`.
  ///   - documentedValue: The value the catalog gives for the byte when it's fixed. Defaults
  ///     to `nil`.
  public init(
    position: Int,
    name: String,
    label: String? = nil,
    value: UInt8,
    valueName: String? = nil,
    isPerGroup: Bool = false,
    documentedValue: UInt8? = nil
  ) {

    self.position = position
    self.name = name
    self.label = label
    self.value = value
    self.valueName = valueName
    self.isPerGroup = isPerGroup
    self.documentedValue = documentedValue

  }

  /// The byte the catalog's explanation gives.
  init(_ byte: RecordDataExplanation.DataByte) {

    self.init(
      position: byte.position,
      name: byte.name.rawValue,
      label: byte.label,
      value: byte.value,
      valueName: byte.tableEntry?.label,
      isPerGroup: byte.isPerGroup,
      documentedValue: byte.documentedValue
    )

  }

}
