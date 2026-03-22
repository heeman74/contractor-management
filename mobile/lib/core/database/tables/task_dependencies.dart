import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'companies.dart';
import 'tasks.dart';

/// Edge table for task-to-task dependency links.
///
/// Synced from backend. Stores FS/SS/FF/SE edges with lag_days.
/// FS = Finish-to-Start (default): successor can only start after predecessor finishes.
/// SS = Start-to-Start: successor can only start after predecessor starts.
/// FF = Finish-to-Finish: successor can only finish after predecessor finishes.
/// SE = Start-to-End: successor can only finish after predecessor starts.
///
/// [lagDays] is positive for lag (delay) and negative for lead (acceleration).
class TaskDependencies extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get companyId => text().references(Companies, #id)();
  TextColumn get predecessorTaskId => text().references(ProjectTasks, #id)();
  TextColumn get successorTaskId => text().references(ProjectTasks, #id)();

  /// Dependency type: FS | SS | FF | SE
  TextColumn get dependencyType => text().withDefault(const Constant('FS'))();

  /// Positive = lag days, negative = lead days
  IntColumn get lagDays => integer().withDefault(const Constant(0))();

  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete for sync tombstone propagation across devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
