import InsteonScheduling

extension ServerOptions {
  /// The home's location, when both coordinates were given.
  var location: GeographicCoordinate? {
    guard let latitude, let longitude else { return nil }
    return GeographicCoordinate(latitude: latitude, longitude: longitude)
  }
}
