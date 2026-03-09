/// Lifecycle state machine for the Job entity.
///
/// Six states represent the full lifecycle from initial quote through payment.
/// Transitions are role-gated on the backend (Admin: all; Contractor: limited
/// forward-only on own jobs; Client: view only).
///
/// The [backendValue] getter provides the snake_case string stored in both
/// the local Drift DB and the backend PostgreSQL column.
enum JobStatus {
  quote,
  scheduled,
  inProgress,
  complete,
  invoiced,
  cancelled;

  /// Parse a [JobStatus] from the snake_case backend/DB string representation.
  ///
  /// Throws [ArgumentError] for unknown values — indicates a schema mismatch
  /// between app version and backend.
  static JobStatus fromString(String value) {
    return switch (value) {
      'quote' => JobStatus.quote,
      'scheduled' => JobStatus.scheduled,
      'in_progress' => JobStatus.inProgress,
      'complete' => JobStatus.complete,
      'invoiced' => JobStatus.invoiced,
      'cancelled' => JobStatus.cancelled,
      _ => throw ArgumentError('Unknown JobStatus: $value'),
    };
  }

  /// The snake_case string stored in the Drift DB and sent to the backend.
  String get backendValue {
    return switch (this) {
      JobStatus.quote => 'quote',
      JobStatus.scheduled => 'scheduled',
      JobStatus.inProgress => 'in_progress',
      JobStatus.complete => 'complete',
      JobStatus.invoiced => 'invoiced',
      JobStatus.cancelled => 'cancelled',
    };
  }

  /// Human-readable label for UI display (kanban column headers, status badges).
  String get displayLabel {
    return switch (this) {
      JobStatus.quote => 'Quote',
      JobStatus.scheduled => 'Scheduled',
      JobStatus.inProgress => 'In Progress',
      JobStatus.complete => 'Complete',
      JobStatus.invoiced => 'Invoiced',
      JobStatus.cancelled => 'Cancelled',
    };
  }
}
