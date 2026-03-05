/// Trade type tags for contractors.
///
/// A contractor can be tagged with multiple trade types.
/// Stored as a comma-separated string in the local Drift database
/// and as a JSON array in the backend PostgreSQL database.
enum TradeType {
  builder,
  electrician,
  plumber,
  hvac,
  painter,
  carpenter,
  roofer,
  landscaper,
  general;

  /// Convert from string stored in DB/API.
  static TradeType fromString(String value) {
    return TradeType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => throw ArgumentError('Unknown TradeType: $value'),
    );
  }

  /// Parse a comma-separated string of trade types (as stored in Drift).
  static List<TradeType> fromCommaSeparated(String? value) {
    if (value == null || value.isEmpty) return [];
    return value
        .split(',')
        .map((s) => fromString(s.trim()))
        .toList();
  }

  /// Serialize a list of trade types to a comma-separated string for Drift.
  static String toCommaSeparated(List<TradeType> types) {
    return types.map((t) => t.name).join(',');
  }
}
