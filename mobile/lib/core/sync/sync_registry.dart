import 'sync_handler.dart';

/// Registry mapping entity type strings to their [SyncHandler] implementations.
///
/// The registry is the extension point for the sync system. Each entity type
/// that participates in offline sync registers exactly one handler here.
///
/// Usage:
/// ```dart
/// final registry = SyncRegistry();
/// registry.register(CompanySyncHandler(dio, db));
/// registry.register(UserSyncHandler(dio, db));
/// // ...
/// final handler = registry.getHandler('company');
/// await handler.push(queueItem);
/// ```
///
/// Adding a new entity type to sync requires only:
/// 1. Creating a [SyncHandler] subclass
/// 2. Calling [register] with an instance of it
/// No changes to [SyncEngine] are needed.
class SyncRegistry {
  final _handlers = <String, SyncHandler>{};

  /// Register a handler for an entity type.
  ///
  /// The handler's [SyncHandler.entityType] is used as the registry key.
  /// Calling register with a duplicate type overwrites the existing handler.
  void register(SyncHandler handler) {
    _handlers[handler.entityType] = handler;
  }

  /// Look up the handler for a given entity type.
  ///
  /// Throws [StateError] if no handler is registered for [entityType].
  /// This is intentional — an unregistered entity type in the queue
  /// indicates a programming error, not a runtime condition.
  SyncHandler getHandler(String entityType) {
    final handler = _handlers[entityType];
    if (handler == null) {
      throw StateError(
        'No SyncHandler registered for entity type: "$entityType". '
        'Registered types: ${_handlers.keys.join(', ')}',
      );
    }
    return handler;
  }

  /// All registered entity type strings.
  ///
  /// Used by [SyncEngine.pullDelta] to enumerate which types to process
  /// in the delta sync response.
  List<String> get registeredTypes => List.unmodifiable(_handlers.keys);
}
