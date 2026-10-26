import Foundation

public struct AccessToken: Codable, Equatable {

  public var value: String

  public var refreshToken: String?

  public var expiresAt: Date

  public init(value: String, refreshToken: String? = nil, expiresAt: Date) {

    self.value = value
    self.refreshToken = refreshToken
    self.expiresAt = expiresAt

  }

  /// Creates a token from an OAuth token response, whose `expires_in` is in seconds.
  public init(
    value: String,
    refreshToken: String? = nil,
    expiresIn: TimeInterval,
    issuedAt: Date = Date()
  ) {

    self.init(
      value: value,
      refreshToken: refreshToken,
      expiresAt: issuedAt.addingTimeInterval(expiresIn)
    )

  }

  public func isExpired(at date: Date) -> Bool {

    return date >= expiresAt

  }

}
