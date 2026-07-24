/// Canonical task lifecycle states and priorities.
///
/// Replaces magic status strings scattered across the projects feature.
/// These values mirror the `status` / `priority` columns defined in the
/// Drift `ProjectTasks` table.
abstract final class TaskStatus {
  static const String notStarted = 'not_started';
  static const String inProgress = 'in_progress';
  static const String complete = 'complete';
  static const String blocked = 'blocked';
  static const String rejected = 'rejected';
}

abstract final class TaskPriority {
  static const String low = 'low';
  static const String medium = 'medium';
  static const String high = 'high';
  static const String urgent = 'urgent';
}

/// Inspection decisions recorded on a task by a GC/admin.
abstract final class InspectionDecision {
  static const String approved = 'approved';
  static const String rejected = 'rejected';
}

/// Attachment kinds stored against a task.
abstract final class TaskAttachmentType {
  static const String photo = 'photo';
  static const String document = 'document';
}
