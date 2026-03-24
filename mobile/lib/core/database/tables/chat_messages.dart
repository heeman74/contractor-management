import 'package:drift/drift.dart';

/// Drift table definition for ChatMessage entities.
///
/// Chat messages are the core content of a [ChatThread]. Each message has
/// a client-generated [id] (UUID v4) used as the idempotency key for
/// offline-first outbox delivery, and a server-assigned [seq] number
/// used for ordering and read receipt tracking.
///
/// Messages are kept trimmed to the latest 100 per thread in local storage
/// (D-13: local cache ceiling). Older messages are loaded on demand via
/// cursor-based pagination against the backend API.
///
/// [status] lifecycle:
///   'pending' — created locally, not yet ACKed by server
///   'sent'    — server ACK received (seq assigned)
///   'failed'  — delivery failed after 3 retries
///
/// Attachment fields are nullable and independent — a message can have
/// text content, an attachment, or both.
class ChatMessages extends Table {
  /// Client-generated UUID v4 — idempotency key for offline outbox.
  TextColumn get id => text()();

  /// Tenant scope — matches JWT companyId.
  TextColumn get companyId => text()();

  /// FK to chat_threads.id — soft reference (no hard Drift FK).
  TextColumn get threadId => text()();

  /// FK to users.id — author of this message.
  TextColumn get senderId => text()();

  /// Display name of the sender at time of send (denormalized for offline reads).
  TextColumn get senderName => text()();

  /// Text body of the message. Nullable — attachment-only messages have no body.
  TextColumn get content => text().nullable()();

  /// Server-assigned monotonic sequence number within the thread.
  /// Used for ordering, read receipt tracking, and missed-message sync.
  IntColumn get seq => integer()();

  /// URL to attachment file (photo, PDF, or annotated photo).
  TextColumn get attachmentUrl => text().nullable()();

  /// Attachment MIME category: 'photo', 'pdf', or 'annotated_photo'.
  TextColumn get attachmentType => text().nullable()();

  /// JSON string of annotation overlay data (non-destructive photo markup).
  /// Stored as TEXT; parsed to `Map&lt;String, dynamic&gt;` at read time.
  TextColumn get annotationData => text().nullable()();

  /// JSON array of user IDs mentioned in this message (e.g. `["uuid1","uuid2"]`).
  TextColumn get mentions =>
      text().withDefault(const Constant('[]'))();

  /// True if the message mentions all members of the thread.
  BoolColumn get mentionAll =>
      boolean().withDefault(const Constant(false))();

  /// Delivery status: 'pending' | 'sent' | 'failed'.
  TextColumn get status =>
      text().withDefault(const Constant('sent'))();

  DateTimeColumn get createdAt => dateTime()();

  /// Soft-delete — server sets this when a message is deleted.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
