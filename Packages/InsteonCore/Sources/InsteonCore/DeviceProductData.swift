import InsteonLinking
import InsteonModem
import InsteonProtocol

/// What a device says about its product in its Product Data Response.
///
/// ```swift
/// if let data = try await network.productData(of: lamp) {
///   print(data.category, data.subcategory, data.productKey.map { "\($0)" } ?? "no product key")
/// }
/// ```
public struct DeviceProductData: Hashable, Sendable {

  /// The device's category.
  public var category: DeviceCategory

  /// The device's subcategory.
  public var subcategory: DeviceSubcategory

  /// The device's product key, or `nil` if it reports none. Many devices leave the product key
  /// out by reporting zeros, which is expected, not a failure.
  public var productKey: ProductKey?

  /// Creates product data.
  ///
  /// - Parameters:
  ///   - category: The device's category.
  ///   - subcategory: The device's subcategory.
  ///   - productKey: The device's product key, or `nil` if it reports none.
  public init(category: DeviceCategory, subcategory: DeviceSubcategory, productKey: ProductKey?) {

    self.category = category
    self.subcategory = subcategory
    self.productKey = productKey

  }

  /// Reads a Product Data Response, taking a product key of zeros as none.
  init(_ data: ProductData) {

    let none: ProductKey = ProductKey(0, 0, 0)

    self.init(
      category: data.category,
      subcategory: data.subcategory,
      productKey: data.productKey == none ? nil : data.productKey
    )

  }

}

extension DeviceNetwork {

  /// Asks a device for its product data with Product Data Request, and waits for its Product
  /// Data Response.
  ///
  /// Listening starts before the request, so the response can't be missed. Not every device
  /// answers the request: one that rejects it, doesn't acknowledge it, or acknowledges it and
  /// sends no response in time gives `nil`. Nothing is recorded in the network's registry or
  /// snapshot; ``identify(_:)`` records what a device reports.
  ///
  /// - Parameter device: The device's address.
  /// - Returns: What the device's response says, or `nil` if it sent none.
  /// - Throws: The modem's error, other than a device's rejection or silence, or
  ///   `CancellationError` if the task is canceled.
  public nonisolated func productData(of device: InsteonAddress) async throws -> DeviceProductData? {

    let modem: any LinkingModem = self.modem
    let timeout: Duration = requestTimeout

    do {

      let data: ProductData? = try await modem.firstReply(
        within: Modem.defaultExtendedRequestTimeout,
        clock: clock,
        after: { () async throws -> Void in

          do {

            _ = try await modem.request(StandardMessage(to: device, command: StandardDirectCommand.productDataRequest), timeout: timeout)

          } catch let error as ModemError {

            // Not every device answers Product Data Request.
            switch error {
            case .deviceRejected, .deviceTimedOut:
              throw NoProductData()
            default:
              throw error
            }

          }

        },
        matching: { (reply: ModemReply) -> ProductData? in

          guard case let .messageReceived(message) = reply, message.sender == device else {

            return nil

          }

          return ProductData(message)

        }
      )

      return data.map { (response: ProductData) -> DeviceProductData in DeviceProductData(response) }

    } catch is NoProductData {

      return nil

    }

  }

}

/// A device that didn't answer Product Data Request.
private struct NoProductData: Error {}
