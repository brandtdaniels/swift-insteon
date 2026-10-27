/// Errors reported by ``Hub`` and ``HubConnection``.
public enum HubError: Error, Hashable, Sendable {

  /// The endpoint's host and port don't form a valid URL, for example because the host is empty
  /// or the port is outside 0 to 65,535.
  case invalidEndpoint(HubEndpoint)

  /// The Hub answered with a non-2xx HTTP status. A `401` means the credentials were rejected.
  case unexpectedStatus(Int)

  /// The Hub's buffer status could not be parsed.
  case malformedBuffer

}
