import InsteonService

/// Wire names and guided wording for why the modem is away. Wording never carries a host,
/// address or credential.
extension ModemUnavailability {
  /// The stable name clients branch on.
  public var wireName: String {
    switch self {
    case .connecting: "connecting"
    case .hubUnreachable: "hubUnreachable"
    case .credentialsRejected: "credentialsRejected"
    case .hubErrorStatus: "hubErrorStatus"
    case .modemUnreachable: "modemUnreachable"
    case .connectionLost: "connectionLost"
    }
  }

  /// Why a command was refused, what the person can do, and that nothing was sent.
  public var refusal: String {
    switch self {
    case .connecting: "The service is still connecting to the Hub or modem, so nothing was sent. Try again in a minute."
    case .hubUnreachable: "The Hub is not answering, so nothing was sent. The service keeps retrying. Check that the Hub is powered on and on the same network."
    case .credentialsRejected: "The Hub rejected its user name and password, so nothing was sent. Check INSTEON_HUB_USERNAME and INSTEON_HUB_PASSWORD in the protected environment file, then restart the service."
    case .hubErrorStatus: "The Hub answered with an error, so nothing was sent. The service keeps retrying. Try again in a minute."
    case .modemUnreachable: "The modem is not answering, so nothing was sent. The service keeps retrying. Check that the modem is connected and powered."
    case .connectionLost: "The connection to the Hub or modem was lost, so nothing was sent. The service keeps retrying. Try again in a minute."
    }
  }

  /// What pages and event streams say while device information may be out of date.
  public var notice: String {
    switch self {
    case .connecting: "The service is connecting to the Hub or modem. Showing saved device information."
    case .hubUnreachable: "The Hub is unreachable. Showing saved device information while the service keeps retrying."
    case .credentialsRejected: "The Hub rejected its user name and password. Showing saved device information. Check INSTEON_HUB_USERNAME and INSTEON_HUB_PASSWORD, then restart the service; it retries every 15 minutes."
    case .hubErrorStatus: "The Hub is answering with errors. Showing saved device information while the service keeps retrying."
    case .modemUnreachable: "The modem is not answering. Showing saved device information while the service keeps retrying."
    case .connectionLost: "The connection to the Hub or modem was lost. Showing saved device information while the service keeps retrying."
    }
  }
}

extension ModemConnectionState {
  /// The cause when the modem is away, or `nil` when it is connected.
  public var cause: ModemUnavailability? {
    if case let .unavailable(cause) = self { cause } else { nil }
  }
}
