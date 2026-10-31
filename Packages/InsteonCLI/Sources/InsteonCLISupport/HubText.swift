import InsteonProtocol

/// What the command says when a request to the Hub gets no answer. Neither message carries
/// the Hub's credentials.
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

  /// For a Hub that answered earlier requests and then stopped, where the command reports the
  /// failure as part of a longer message and the Hub's address and device are given elsewhere.
  public static let stoppedAnsweringInline: String = "the Hub stopped answering, most likely while a device that's out of range didn't answer; try again"

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

}
