/// Why a message that was sent didn't get the answer it needs.
public enum DeliveryFailure: Hashable, Sendable {

  /// The modem rejected the message with a NAK (`0x15`), so it never left the modem.
  case modemRejected

  /// The device rejected the message with a NAK while it searches its ALL-Link database, which
  /// ends when the search does.
  case deviceBusy

  /// The device never acknowledged the message, so it may have acted on it.
  case noDeviceAcknowledgment

  /// The device rejected the message with a NAK for another reason.
  case deviceRejected

}

/// Whether to send a message again.
public enum ResendDecision: Hashable, Sendable {

  /// Send the message again.
  case resend

  /// Report the failure and send nothing more.
  case doNotResend

}

/// Decides whether a failed message is sent again.
///
/// A message that may have reached the device is sent again only if sending it twice leaves the
/// device as sending it once does, which the catalog marks as idempotent. A message the modem
/// rejected, or a busy device rejected while it searches its ALL-Link database, never acted, so
/// it's sent again whatever its entry marks. A missing mark reads as not idempotent.
///
/// ```swift
/// let decision = ResendPolicy.decision(after: .noDeviceAcknowledgment, isIdempotent: true)
/// // resend
/// ```
public enum ResendPolicy {

  /// Decides whether to send a message again after it fails.
  ///
  /// - Parameters:
  ///   - failure: How it failed.
  ///   - isIdempotent: Whether the catalog marks the message idempotent, or `nil` if it marks
  ///     nothing.
  /// - Returns: Whether to send it again.
  public static func decision(after failure: DeliveryFailure, isIdempotent: Bool?) -> ResendDecision {

    switch failure {
    case .modemRejected, .deviceBusy:
      .resend
    case .noDeviceAcknowledgment:
      isIdempotent == true ? .resend : .doNotResend
    case .deviceRejected:
      .doNotResend
    }

  }

}
