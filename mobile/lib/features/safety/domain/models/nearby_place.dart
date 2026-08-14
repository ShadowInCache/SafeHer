/// A real, named safety location returned by the backend's
/// `/api/v1/safety/nearby` lookup (OpenStreetMap data). Every field here comes
/// from the data source — nothing is inferred or filled in with a placeholder.
class NearbyPlace {
  const NearbyPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.distanceMetres,
    this.phone,
    this.address,
    this.openHours,
  });

  final String id;
  final String name;
  final NearbyPlaceCategory category;
  final double latitude;
  final double longitude;
  final int distanceMetres;

  /// Null when OSM has no phone tag for this place — the UI hides the Call
  /// action rather than showing a dead button.
  final String? phone;
  final String? address;
  final String? openHours;

  String get distanceLabel {
    if (distanceMetres < 1000) return '$distanceMetres m';
    return '${(distanceMetres / 1000).toStringAsFixed(1)} km';
  }
}

enum NearbyPlaceCategory {
  police,
  hospital,
  pharmacy,
  fireStation,
  transit,
  shelter;

  static NearbyPlaceCategory? fromWire(String value) => switch (value) {
    'police' => NearbyPlaceCategory.police,
    'hospital' => NearbyPlaceCategory.hospital,
    'pharmacy' => NearbyPlaceCategory.pharmacy,
    'fire_station' => NearbyPlaceCategory.fireStation,
    'transit' => NearbyPlaceCategory.transit,
    'shelter' => NearbyPlaceCategory.shelter,
    _ => null,
  };

  String get wireValue => switch (this) {
    NearbyPlaceCategory.police => 'police',
    NearbyPlaceCategory.hospital => 'hospital',
    NearbyPlaceCategory.pharmacy => 'pharmacy',
    NearbyPlaceCategory.fireStation => 'fire_station',
    NearbyPlaceCategory.transit => 'transit',
    NearbyPlaceCategory.shelter => 'shelter',
  };

  String get label => switch (this) {
    NearbyPlaceCategory.police => 'Police',
    NearbyPlaceCategory.hospital => 'Hospital',
    NearbyPlaceCategory.pharmacy => 'Pharmacy',
    NearbyPlaceCategory.fireStation => 'Fire station',
    NearbyPlaceCategory.transit => 'Transit',
    NearbyPlaceCategory.shelter => 'Shelter',
  };
}
