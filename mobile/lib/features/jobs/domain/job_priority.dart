/// Priority levels for a job. Stored as the lowercase string in the DB.
abstract final class JobPriority {
  static const String low = 'low';
  static const String medium = 'medium';
  static const String high = 'high';
}
