import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

// The values InsteonCore's API takes and gives that are pure data, with no behavior to hide.
// Each is the lower-level module's type under the same name, so a front end that depends only
// on InsteonCore can name it, and code that also imports the lower-level module sees one type.

// MARK: - Addresses, groups and identities

/// A device's three-byte Insteon address, such as `1A.2B.3C`.
public typealias InsteonAddress = InsteonProtocol.InsteonAddress

/// The number of an ALL-Link group, from 0 through 255.
public typealias AllLinkGroupNumber = InsteonProtocol.AllLinkGroupNumber

/// A device's category, such as `0x01` for dimmable lighting control.
public typealias DeviceCategory = InsteonProtocol.DeviceCategory

/// A device's subcategory within its category.
public typealias DeviceSubcategory = InsteonProtocol.DeviceSubcategory

/// The firmware version a device reports.
public typealias FirmwareVersion = InsteonProtocol.FirmwareVersion

/// The product key a device reports in its Product Data Response.
public typealias ProductKey = InsteonProtocol.ProductKey

/// The Insteon engine a device runs: i1, i2 or i2CS.
public typealias InsteonEngine = InsteonProtocol.InsteonEngine

/// The category, subcategory and firmware version a device reported.
public typealias ReportedIdentity = InsteonProtocol.ReportedIdentity

/// The identity the modem reports for Get IM Info: its Insteon ID, category, subcategory and
/// firmware version.
public typealias ModemInfo = InsteonProtocol.ModemInfo

/// Why a device rejected a direct message, from the cmd2 of its NAK.
public typealias NAKReason = InsteonProtocol.NAKReason

// MARK: - Links

/// The modem's report of a link it made or removed.
public typealias AllLinkingCompleted = InsteonProtocol.AllLinkingCompleted

/// The modem's role in a link it reported: controller, responder or deleted.
public typealias AllLinkMode = InsteonProtocol.AllLinkMode

/// A link between the modem and a device, by the modem's role and group.
public typealias ModemLink = InsteonLinking.ModemLink

/// The modem's role in a link: controller or responder.
public typealias ModemRole = InsteonLinking.ModemRole

/// The modem's role in a link made with a device's SET button: controller, responder, or
/// either, as the device decides.
public typealias ManualLinkingRole = InsteonLinking.ManualLinkingRole

/// Whether a link is being made or removed.
public typealias LinkingDirection = InsteonLinking.LinkingDirection

// MARK: - The Insteon device catalog's data

/// What the Insteon device catalog says about a device with a reported identity.
public typealias DeviceDescription = InsteonDeviceCatalog.DeviceDescription

/// A product's entry in the Insteon device catalog.
public typealias DeviceProfile = InsteonDeviceCatalog.DeviceProfile

/// What the Insteon device catalog says about linking, unlinking and resetting a product.
public typealias DeviceLifecycle = InsteonDeviceCatalog.DeviceLifecycle

/// A procedure in a product's lifecycle, such as linking or a factory reset: its steps, in order.
///
/// Named on its own so a module that reaches the catalog only through InsteonCore can name it.
public typealias LifecycleProcedure = InsteonDeviceCatalog.DeviceLifecycle.Procedure

/// A step of a lifecycle procedure, done on a device, with what the device does in answer.
public typealias LifecycleStep = InsteonDeviceCatalog.DeviceLifecycle.Step

/// Something a factory reset erases, as the Insteon device catalog gives it.
public typealias LifecycleErasure = InsteonDeviceCatalog.DeviceLifecycle.Erasure

/// What one data byte of an ALL-Link record means, as the Insteon device catalog gives it.
public typealias RecordDataByte = InsteonDeviceCatalog.RecordDataExplanation.DataByte

/// The product key the Insteon device catalog gives a product, or that it reports none.
public typealias ProductKeyEntry = InsteonDeviceCatalog.DeviceIdentity.ProductKeyEntry

/// What the data bytes of an ALL-Link record mean, as the Insteon device catalog gives them.
public typealias RecordDataExplanation = InsteonDeviceCatalog.RecordDataExplanation

/// A version of the Insteon device catalog, such as `0.6.26`.
public typealias DeviceCatalogVersion = InsteonDeviceCatalog.DeviceCatalogVersion
