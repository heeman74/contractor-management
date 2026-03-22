import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart'
    show
        TradeScope,
        ProjectTask,
        TaskDependency,
        ProjectZone,
        TradeScopeDao,
        TaskDao,
        TaskDependencyDao,
        ProjectZoneDao;
import '../../../../core/di/service_locator.dart';

// ---------------------------------------------------------------------------
// DAO providers
// ---------------------------------------------------------------------------

/// Provider exposing [TaskDependencyDao] singleton from GetIt.
/// (GetIt<->Riverpod tradeoff documented: DAO is registered at startup;
/// accessing via provider makes it testable via ProviderScope overrides.)
final taskDependencyDaoProvider = Provider<TaskDependencyDao>((ref) {
  return getIt<TaskDependencyDao>();
});

/// Provider exposing [ProjectZoneDao] singleton from GetIt.
final projectZoneDaoProvider = Provider<ProjectZoneDao>((ref) {
  return getIt<ProjectZoneDao>();
});

/// Re-export TradeScopeDao provider for gantt use (avoids circular import).
final ganttTradeScopeDaoProvider = Provider<TradeScopeDao>((ref) {
  return getIt<TradeScopeDao>();
});

/// Re-export TaskDao provider for gantt use.
final ganttTaskDaoProvider = Provider<TaskDao>((ref) {
  return getIt<TaskDao>();
});

// ---------------------------------------------------------------------------
// Domain models
// ---------------------------------------------------------------------------

/// Information about a task pair that shares a zone on the same date.
///
/// Used to show conflict warnings on the Gantt chart.
class ConflictInfo {
  final String zone1TaskId;
  final String zone2TaskId;
  final String zoneName;
  final DateTime conflictDate;
  final String trade1Name;
  final String trade2Name;

  const ConflictInfo({
    required this.zone1TaskId,
    required this.zone2TaskId,
    required this.zoneName,
    required this.conflictDate,
    required this.trade1Name,
    required this.trade2Name,
  });
}

/// Aggregated state for the Gantt chart — all data needed to render and
/// interact with the project timeline.
class GanttDataState {
  final List<TradeScope> scopes;
  final Map<String, List<ProjectTask>> tasksByScope;
  final List<TaskDependency> dependencies;
  final List<ProjectZone> zones;
  final List<ConflictInfo> conflicts;

  /// Set of task IDs involved in at least one zone conflict — used by
  /// [GanttPainter] to draw orange conflict borders on affected bars.
  Set<String> get conflictTaskIds => {
        for (final c in conflicts) ...[c.zone1TaskId, c.zone2TaskId],
      };

  const GanttDataState({
    required this.scopes,
    required this.tasksByScope,
    required this.dependencies,
    required this.zones,
    required this.conflicts,
  });

  GanttDataState copyWith({
    List<TradeScope>? scopes,
    Map<String, List<ProjectTask>>? tasksByScope,
    List<TaskDependency>? dependencies,
    List<ProjectZone>? zones,
    List<ConflictInfo>? conflicts,
  }) {
    return GanttDataState(
      scopes: scopes ?? this.scopes,
      tasksByScope: tasksByScope ?? this.tasksByScope,
      dependencies: dependencies ?? this.dependencies,
      zones: zones ?? this.zones,
      conflicts: conflicts ?? this.conflicts,
    );
  }

  factory GanttDataState.empty() => const GanttDataState(
        scopes: [],
        tasksByScope: {},
        dependencies: [],
        zones: [],
        conflicts: [],
      );
}

// ---------------------------------------------------------------------------
// GanttDataNotifier — AsyncNotifier for a single projectId
// ---------------------------------------------------------------------------

/// Async notifier that aggregates all streams needed for the Gantt chart.
///
/// Watches:
/// - TradeScopeDao.watchScopesByProject — reactive list of trade scopes
/// - TaskDao.watchTasksByScope — one stream per scope
/// - TaskDependencyDao.watchByProject — all dependency edges
/// - ProjectZoneDao.watchByProject — zones for conflict detection
///
/// Computes conflicts locally: groups tasks by (zoneId, dueDate), flags
/// groups containing tasks from different trade scopes.
class GanttDataNotifier extends AsyncNotifier<GanttDataState> {
  final String projectId;

  GanttDataNotifier(this.projectId);

  @override
  Future<GanttDataState> build() async {
    final scopeDao = ref.watch(ganttTradeScopeDaoProvider);
    final taskDao = ref.watch(ganttTaskDaoProvider);
    final depDao = ref.watch(taskDependencyDaoProvider);
    final zoneDao = ref.watch(projectZoneDaoProvider);

    // Initial data fetch from all streams
    final scopes = await scopeDao.watchScopesByProject(projectId).first;
    final deps = await depDao.watchByProject(projectId).first;
    final zones = await zoneDao.watchByProject(projectId).first;

    // Fetch tasks for all scopes
    final tasksByScope = <String, List<ProjectTask>>{};
    for (final scope in scopes) {
      tasksByScope[scope.id] =
          await taskDao.watchTasksByScope(scope.id).first;
    }

    final conflicts = _computeConflicts(tasksByScope, scopes, zones);

    // Subscribe to live updates (skip first emission — already fetched above)
    final scopeSub = scopeDao.watchScopesByProject(projectId).skip(1).listen(
          (newScopes) => _onScopesChanged(newScopes, taskDao),
          onError: (Object e, StackTrace st) => state = AsyncError(e, st),
        );
    final depSub = depDao.watchByProject(projectId).skip(1).listen(
          _onDepsChanged,
          onError: (Object e, StackTrace st) => state = AsyncError(e, st),
        );
    final zoneSub = zoneDao.watchByProject(projectId).skip(1).listen(
          _onZonesChanged,
          onError: (Object e, StackTrace st) => state = AsyncError(e, st),
        );

    ref.onDispose(() {
      scopeSub.cancel();
      depSub.cancel();
      zoneSub.cancel();
    });

    return GanttDataState(
      scopes: scopes,
      tasksByScope: tasksByScope,
      dependencies: deps,
      zones: zones,
      conflicts: conflicts,
    );
  }

  void _onScopesChanged(List<TradeScope> scopes, TaskDao taskDao) {
    final current = state.value;
    if (current == null) return;

    final updatedTasks = Map<String, List<ProjectTask>>.from(
      current.tasksByScope,
    );

    // Add empty lists for new scopes and subscribe to their tasks
    for (final scope in scopes) {
      if (!updatedTasks.containsKey(scope.id)) {
        updatedTasks[scope.id] = [];
        taskDao.watchTasksByScope(scope.id).listen(
          (tasks) {
            final s = state.value;
            if (s == null) return;
            final updated =
                Map<String, List<ProjectTask>>.from(s.tasksByScope);
            updated[scope.id] = tasks;
            state = AsyncData(
              s.copyWith(
                tasksByScope: updated,
                conflicts: _computeConflicts(updated, s.scopes, s.zones),
              ),
            );
          },
        );
      }
    }

    // Remove deleted scopes
    final scopeIds = scopes.map((s) => s.id).toSet();
    updatedTasks.removeWhere((key, _) => !scopeIds.contains(key));

    final conflicts = _computeConflicts(updatedTasks, scopes, current.zones);
    state = AsyncData(current.copyWith(
      scopes: scopes,
      tasksByScope: updatedTasks,
      conflicts: conflicts,
    ));
  }

  void _onDepsChanged(List<TaskDependency> deps) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(dependencies: deps));
  }

  void _onZonesChanged(List<ProjectZone> zones) {
    final current = state.value;
    if (current == null) return;
    final conflicts =
        _computeConflicts(current.tasksByScope, current.scopes, zones);
    state = AsyncData(current.copyWith(zones: zones, conflicts: conflicts));
  }

  /// Detect zone conflicts: tasks from different scopes assigned to the same
  /// zone on the same calendar date.
  ///
  /// Only tasks with both [zoneId] and [dueDate] set are considered.
  List<ConflictInfo> _computeConflicts(
    Map<String, List<ProjectTask>> tasksByScope,
    List<TradeScope> scopes,
    List<ProjectZone> zones,
  ) {
    final zoneNames = {for (final z in zones) z.id: z.name};
    final scopeNames = {for (final s in scopes) s.id: s.tradeName};

    // Map from taskId to scopeId
    final taskScopeMap = <String, String>{};
    for (final entry in tasksByScope.entries) {
      for (final task in entry.value) {
        taskScopeMap[task.id] = entry.key;
      }
    }

    // Group tasks by (zoneId, dueDate) key
    final groups = <String, List<ProjectTask>>{};
    for (final tasks in tasksByScope.values) {
      for (final task in tasks) {
        if (task.zoneId == null || task.dueDate == null) continue;
        final key =
            '${task.zoneId}|${task.dueDate!.toIso8601String().substring(0, 10)}';
        groups.putIfAbsent(key, () => []).add(task);
      }
    }

    final conflicts = <ConflictInfo>[];
    for (final entry in groups.entries) {
      final tasks = entry.value;
      if (tasks.length < 2) continue;

      final scopeIdsInGroup = tasks.map((t) => taskScopeMap[t.id]).toSet();
      if (scopeIdsInGroup.length <= 1) continue;

      final parts = entry.key.split('|');
      final zoneId = parts[0];
      final zoneName = zoneNames[zoneId] ?? zoneId;

      for (int i = 0; i < tasks.length; i++) {
        for (int j = i + 1; j < tasks.length; j++) {
          final scopeId1 = taskScopeMap[tasks[i].id];
          final scopeId2 = taskScopeMap[tasks[j].id];
          if (scopeId1 == scopeId2) continue;

          conflicts.add(ConflictInfo(
            zone1TaskId: tasks[i].id,
            zone2TaskId: tasks[j].id,
            zoneName: zoneName,
            conflictDate: tasks[i].dueDate!,
            trade1Name: scopeNames[scopeId1] ?? 'Trade 1',
            trade2Name: scopeNames[scopeId2] ?? 'Trade 2',
          ));
        }
      }
    }

    return conflicts;
  }
}

/// Family provider for [GanttDataNotifier], keyed by [projectId].
///
/// Auto-disposed when the Gantt screen is popped.
/// Uses Riverpod 3 family pattern: factory function receives arg and returns
/// a GanttDataNotifier initialized with that projectId.
final ganttDataProvider = AsyncNotifierProvider.autoDispose
    .family<GanttDataNotifier, GanttDataState, String>(
  (projectId) => GanttDataNotifier(projectId),
);
