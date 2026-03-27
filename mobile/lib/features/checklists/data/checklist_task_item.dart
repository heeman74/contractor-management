import '../../../core/database/app_database.dart';

/// Parsed checklist task item from [DailyChecklist.checklistJson].
///
/// Each item represents a single task within a daily AI checklist,
/// with priority, duration estimate, materials, and dependency info.
class ChecklistTaskItem {
  final String taskId;
  final String title;
  final int priority;
  final String estimatedDuration;
  final List<String> materials;
  final bool photoRequired;
  final String dependencyStatus;
  final String projectName;

  const ChecklistTaskItem({
    required this.taskId,
    required this.title,
    required this.priority,
    required this.estimatedDuration,
    required this.materials,
    required this.photoRequired,
    required this.dependencyStatus,
    required this.projectName,
  });

  bool get isBlocked => dependencyStatus.toLowerCase() == 'blocked';

  /// Parse a JSON task object from the checklist into a [ChecklistTaskItem].
  factory ChecklistTaskItem.fromJson(
    Map<String, dynamic> json,
    DailyChecklist checklist,
  ) {
    final rawMaterials = json['materials_needed'];
    final materials = rawMaterials is List
        ? rawMaterials.whereType<String>().toList()
        : <String>[];

    return ChecklistTaskItem(
      taskId: _field(json, 'task_id', ''),
      title: _field(json, 'title', 'Unnamed task'),
      priority: _field(json, 'priority', 3),
      estimatedDuration: _field(json, 'estimated_duration', ''),
      materials: materials,
      photoRequired: _field(json, 'photo_required', false),
      dependencyStatus: _field(json, 'dependency_status', 'ok'),
      projectName: _field(json, 'project_name', 'Project'),
    );
  }

  /// Type-safe JSON field accessor with a default fallback.
  static T _field<T>(Map<String, dynamic> json, String key, T defaultValue) {
    final v = json[key];
    return v is T ? v : defaultValue;
  }
}
