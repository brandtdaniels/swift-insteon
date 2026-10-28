import InsteonProtocol

/// Something a device reported, read through its device profile.
public enum DeviceEvent: Hashable, Sendable {

  /// A device reported its identity: when its SET button was held, in reply to an ID
  /// request, in a heartbeat broadcast, or when its status changed. Carries the profile its
  /// identity matches, or `nil` if the database has none.
  case identified(InsteonAddress, profile: DeviceProfile?)

  /// A device sent a command to one of its groups, with what its profile says the command
  /// means, or `nil` if the device's profile isn't known or doesn't say.
  case groupCommand(GroupCommand, event: DeviceEventName?)

  /// A device sent its periodic heartbeat, as a heartbeat broadcast or as a command to the
  /// heartbeat group its profile gives.
  case heartbeat(InsteonAddress)

  /// A device's status changed. Ask the device for its new status with
  /// `StandardDirectCommand.statusRequest(variant:)`.
  case statusChanged(InsteonAddress)

}
