import InsteonCore

/// What the command says about a Hub: when a request to it gets no answer, and what came of
/// asking it for Get IM Info. No message carries the Hub's credentials.
public enum HubText {

  /// For a Hub that didn't answer any request, as when its address changed.
  ///
  /// - Parameters:
  ///   - host: The Hub's host.
  ///   - port: The Hub's port.
  /// - Returns: A message that names the Hub's address and how to find it again.
  public static func unanswered(host: String, port: Int) -> String {

    "The Hub at \(host):\(port) didn't answer. If its address changed, 'insteon discover' finds it."

  }

  /// For a Hub that answered earlier requests and then stopped, as when its modem is still
  /// sending a message to a device that doesn't answer.
  ///
  /// - Parameters:
  ///   - host: The Hub's host.
  ///   - port: The Hub's port.
  ///   - device: The device the command was for, if it was for one.
  /// - Returns: A message that names the device, or the Hub's address for a command that isn't
  ///   for a device, and says to try again.
  public static func stoppedAnswering(host: String, port: Int, device: InsteonAddress?) -> String {

    guard let device else {

      return "The Hub at \(host):\(port) stopped answering partway through the command. Try again."

    }

    return "The Hub stopped answering while it was waiting for \(device). Check that the device is powered and in range, then try again."

  }

  /// The message for a Hub that stopped answering partway through a command, or never
  /// answered, or `nil` for any other error, which describes itself.
  ///
  /// - Parameters:
  ///   - error: The error the session with the Hub threw.
  ///   - host: The Hub's host.
  ///   - port: The Hub's port.
  ///   - device: The device the command was for, if it was for one, which a Hub that stopped
  ///     answering is most likely waiting on.
  /// - Returns: The message, or `nil`.
  public static func failure(_ error: any Error, host: String, port: Int, device: InsteonAddress?) -> String? {

    switch HubFailure(error) {
    case .stoppedAnswering?:
      // The Hub answered earlier in the run, so it's busy rather than gone, most likely
      // with a device that doesn't answer; 'insteon discover' wouldn't help.
      stoppedAnswering(host: host, port: port, device: device)
    case .unanswered?:
      // URLSession's own message, such as "The request timed out.", doesn't say it was the
      // Hub.
      unanswered(host: host, port: port)
    case nil:
      nil
    }

  }

  /// What `insteon discover --identify` says about a Hub it asked, or didn't ask, for Get IM
  /// Info, without its credentials, or `nil` when there's nothing to say: the Hub was
  /// identified, which the table shows, or the person declined.
  ///
  /// - Parameters:
  ///   - outcome: What came of it.
  ///   - host: The Hub's host.
  ///   - port: The Hub's port.
  ///   - message: Describes an error.
  /// - Returns: The note, or `nil`.
  public static func identification(_ outcome: HubIdentification, host: String, port: Int, message: (any Error) -> String) -> String? {

    let address = "\(host):\(port)"

    switch outcome {
    case .identified, .declined:
      return nil
    case .skippedNonPrivateAddress:
      return "\(host) isn't a private address, so it wasn't sent the password."
    case .skippedNonHubPort:
      return "\(address) isn't on the Hub's port, \(HubLocation.defaultPort), so it wasn't sent the password. "
        + "'insteon discover --identify \(address)' sends it."
    case .didNotAnswer:
      return "\(address) didn't answer Get IM Info in time."
    case let .rejected(error), let .failed(error):
      return "\(address): \(message(error))"
    }

  }

}

extension HubAddress {

  /// Whether this is the Hub at a host and port, with the Hub's port, 25105, when the address
  /// gives none.
  ///
  /// - Parameters:
  ///   - host: The Hub's host.
  ///   - port: The Hub's port.
  /// - Returns: `true` if it's the same Hub.
  public func matches(host: String, port: Int) -> Bool {

    self.host == host && (self.port ?? HubLocation.defaultPort) == port

  }

}
