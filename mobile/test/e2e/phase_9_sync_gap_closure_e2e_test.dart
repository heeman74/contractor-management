// Phase 9 E2E: Sync Engine Gap Closure
//
// Covers INFRA-04, SCHED-03, FIELD-02, BIZ-01, BIZ-03:
// - pullDelta() processes all 15 entity types from the loop
// - JobSyncHandler maps GPS fields (gpsLatitude, gpsLongitude, gpsAddress)
//   and FK fields (quoteId, invoiceId) into Drift
// - Per-entity failure skips failing entity without aborting other types
// - Sync cursor updates to server_timestamp after all types attempted
// - Booking cross-device propagation (SCHED-03)
// - Quote/Invoice cross-device propagation (BIZ-01, BIZ-03)
//
// Strategy: Real Drift in-memory DB. Real SyncRegistry wired with ALL real
// handlers. Mock DioClient/Dio for HTTP layer. Direct await on pullDelta()
// (not pumpAndSettle — Drift streams never settle).

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/network/dio_client.dart';
import 'package:contractorhub/core/sync/connectivity_service.dart';
import 'package:contractorhub/core/sync/handlers/attachment_sync_handler.dart';
import 'package:contractorhub/core/sync/handlers/company_sync_handler.dart';
import 'package:contractorhub/core/sync/handlers/note_sync_handler.dart';
import 'package:contractorhub/core/sync/handlers/time_entry_sync_handler.dart';
import 'package:contractorhub/core/sync/handlers/user_role_sync_handler.dart';
import 'package:contractorhub/core/sync/handlers/user_sync_handler.dart';
import 'package:contractorhub/core/sync/sync_engine.dart';
import 'package:contractorhub/core/sync/sync_registry.dart';
import 'package:contractorhub/features/invoices/data/invoice_line_item_sync_handler.dart';
import 'package:contractorhub/features/invoices/data/invoice_sync_handler.dart';
import 'package:contractorhub/features/jobs/data/client_profile_sync_handler.dart';
import 'package:contractorhub/features/jobs/data/job_request_sync_handler.dart';
import 'package:contractorhub/features/jobs/data/job_sync_handler.dart';
import 'package:contractorhub/features/quotes/data/quote_line_item_sync_handler.dart';
import 'package:contractorhub/features/quotes/data/quote_sync_handler.dart';
import 'package:contractorhub/features/schedule/data/booking_sync_handler.dart';
import 'package:contractorhub/features/schedule/data/job_site_sync_handler.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockDioClient extends Mock implements DioClient {}

class MockDio extends Mock implements Dio {}

class MockConnectivityService extends Mock implements ConnectivityService {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Open an in-memory Drift DB for testing.
AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

/// Build a [SyncRegistry] wired with ALL 15 real handlers against [db].
/// Handlers that require DioClient use [mockDioClient].
SyncRegistry _buildRegistry(AppDatabase db, MockDioClient mockDioClient) {
  final registry = SyncRegistry();
  registry.register(CompanySyncHandler(mockDioClient, db));
  registry.register(UserSyncHandler(mockDioClient, db));
  registry.register(UserRoleSyncHandler(mockDioClient, db));
  registry.register(JobSyncHandler(mockDioClient, db));
  registry.register(ClientProfileSyncHandler(mockDioClient, db));
  registry.register(JobRequestSyncHandler(mockDioClient, db));
  registry.register(BookingSyncHandler(mockDioClient, db));
  registry.register(JobSiteSyncHandler(db));
  registry.register(NoteSyncHandler(mockDioClient, db));
  registry.register(TimeEntrySyncHandler(mockDioClient, db));
  registry.register(QuoteSyncHandler(mockDioClient, db));
  registry.register(InvoiceSyncHandler(mockDioClient, db));
  registry.register(AttachmentSyncHandler(db));
  registry.register(QuoteLineItemSyncHandler(db));
  registry.register(InvoiceLineItemSyncHandler(db));
  return registry;
}

// ---------------------------------------------------------------------------
// Shared UUIDs used in mock data
// ---------------------------------------------------------------------------

const _companyId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _userId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const _userRoleId = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const _jobId = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const _bookingId = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _jobSiteId = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
const _jobNoteId = '11111111-1111-1111-1111-111111111111';
const _attachmentId = '22222222-2222-2222-2222-222222222222';
const _timeEntryId = '33333333-3333-3333-3333-333333333333';
const _clientProfileId = '44444444-4444-4444-4444-444444444444';
const _jobRequestId = '55555555-5555-5555-5555-555555555555';
const _quoteId = '66666666-6666-6666-6666-666666666666';
const _quoteLineItemId = '77777777-7777-7777-7777-777777777777';
const _invoiceId = '88888888-8888-8888-8888-888888888888';
const _invoiceLineItemId = '99999999-9999-9999-9999-999999999999';

const _serverTimestamp = '2026-03-14T12:00:00Z';

/// Full mock sync response with all 15 entity types.
///
/// The job entity includes GPS fields and quote_id/invoice_id FKs.
/// Quotes and invoices include nested line_items for QuoteSyncHandler/InvoiceSyncHandler.
/// quote_line_items and invoice_line_items are flat arrays for the flat handlers.
Map<String, dynamic> _buildFullMockResponse() => {
      'server_timestamp': _serverTimestamp,
      'companies': [
        {
          'id': _companyId,
          'name': 'Test Corp',
          'email': 'test@corp.com',
          'phone': null,
          'address': null,
          'abn': null,
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ],
      'users': [
        {
          'id': _userId,
          'company_id': _companyId,
          'email': 'worker@corp.com',
          'full_name': 'Test Worker',
          'phone': null,
          'trade_types': null,
          'is_active': true,
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ],
      'user_roles': [
        {
          'id': _userRoleId,
          'company_id': _companyId,
          'user_id': _userId,
          'role': 'contractor',
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ],
      'jobs': [
        {
          'id': _jobId,
          'company_id': _companyId,
          'client_id': null,
          'contractor_id': _userId,
          'description': 'Fix the plumbing',
          'trade_type': 'plumbing',
          'status': 'scheduled',
          'status_history': '[]',
          'priority': 'medium',
          'purchase_order_number': null,
          'external_reference': null,
          'tags': '[]',
          'notes': null,
          'gps_latitude': 37.7749,
          'gps_longitude': -122.4194,
          'gps_address': '123 Test St',
          'quote_id': _quoteId,
          'invoice_id': _invoiceId,
          'estimated_duration_minutes': 120,
          'scheduled_completion_date': null,
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ],
      'bookings': [
        {
          'id': _bookingId,
          'company_id': _companyId,
          'contractor_id': _userId,
          'job_id': _jobId,
          'job_site_id': null,
          'time_range_start': '2026-03-14T08:00:00Z',
          'time_range_end': '2026-03-14T10:00:00Z',
          'day_index': null,
          'parent_booking_id': null,
          'notes': null,
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ],
      'job_sites': [
        {
          'id': _jobSiteId,
          'company_id': _companyId,
          'address': '456 Job Site Ave',
          'latitude': null,
          'longitude': null,
          'name': 'Main Site',
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ],
      'job_notes': [
        {
          'id': _jobNoteId,
          'company_id': _companyId,
          'job_id': _jobId,
          'author_id': _userId,
          'body': 'Note about the job',
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ],
      'time_entries': [
        {
          'id': _timeEntryId,
          'company_id': _companyId,
          'job_id': _jobId,
          'contractor_id': _userId,
          'clocked_in_at': '2026-03-14T08:00:00Z',
          'clocked_out_at': '2026-03-14T10:00:00Z',
          'duration_seconds': 7200,
          'session_status': 'completed',
          'adjustment_log': null,
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ],
      'attachments': [
        {
          'id': _attachmentId,
          'company_id': _companyId,
          'note_id': _jobNoteId,
          'attachment_type': 'image',
          'local_path': '',
          'thumbnail_path': null,
          'caption': null,
          'upload_status': 'uploaded',
          'remote_url': '/files/attachments/test.jpg',
          'sort_order': 0,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ],
      'client_profiles': [
        {
          'id': _clientProfileId,
          'company_id': _companyId,
          'user_id': _userId,
          'billing_address': null,
          'tags': '[]',
          'admin_notes': null,
          'referral_source': null,
          'preferred_contractor_id': null,
          'preferred_contact_method': null,
          'average_rating': null,
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ],
      'job_requests': [
        {
          'id': _jobRequestId,
          'company_id': _companyId,
          'client_id': null,
          'description': 'Fix the pipes',
          'trade_type': 'plumbing',
          'urgency': 'standard',
          'preferred_date_start': null,
          'preferred_date_end': null,
          'budget_min': null,
          'budget_max': null,
          'photos': null,
          'status': 'pending',
          'decline_reason': null,
          'decline_message': null,
          'converted_job_id': null,
          'submitted_name': null,
          'submitted_email': 'client@example.com',
          'submitted_phone': null,
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ],
      'quotes': [
        {
          'id': _quoteId,
          'company_id': _companyId,
          'job_id': _jobId,
          'status': 'draft',
          'revision_number': 1,
          'tax_rate': 0.1,
          'discount_type': null,
          'discount_value': null,
          'expiry_date': null,
          'sent_at': null,
          'viewed_at': null,
          'approved_at': null,
          'declined_at': null,
          'decline_reason': null,
          'decline_detail': null,
          'admin_notes': null,
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
          'line_items': [
            {
              'id': _quoteLineItemId,
              'company_id': _companyId,
              'quote_id': _quoteId,
              'item_type': 'labour',
              'description': 'Labour charge',
              'quantity': 2.0,
              'unit': 'hours',
              'unit_price': 100.0,
              'sort_order': 0,
              'version': 1,
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
              'deleted_at': null,
            },
          ],
        },
      ],
      'quote_line_items': [
        {
          'id': _quoteLineItemId,
          'company_id': _companyId,
          'quote_id': _quoteId,
          'item_type': 'labour',
          'description': 'Labour charge',
          'quantity': 2.0,
          'unit': 'hours',
          'unit_price': 100.0,
          'sort_order': 0,
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ],
      'invoices': [
        {
          'id': _invoiceId,
          'company_id': _companyId,
          'job_id': _jobId,
          'invoice_number': 'INV-001',
          'status': 'unpaid',
          'tax_rate': 0.1,
          'discount_type': null,
          'discount_value': null,
          'issued_at': '2026-03-14T00:00:00Z',
          'due_date': '2026-04-14T00:00:00Z',
          'finalized_at': null,
          'quote_id': null,
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
          'line_items': [
            {
              'id': _invoiceLineItemId,
              'company_id': _companyId,
              'invoice_id': _invoiceId,
              'item_type': 'labour',
              'description': 'Labour charge',
              'quantity': 2.0,
              'unit': 'hours',
              'unit_price': 100.0,
              'sort_order': 0,
              'version': 1,
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
              'deleted_at': null,
            },
          ],
        },
      ],
      'invoice_line_items': [
        {
          'id': _invoiceLineItemId,
          'company_id': _companyId,
          'invoice_id': _invoiceId,
          'item_type': 'labour',
          'description': 'Labour charge',
          'quantity': 2.0,
          'unit': 'hours',
          'unit_price': 100.0,
          'sort_order': 0,
          'version': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ],
    };

/// Stub [mockDio] to return [data] on GET /sync.
void _stubSyncResponse(MockDio mockDio, Map<String, dynamic> data) {
  when(
    () => mockDio.get<Map<String, dynamic>>(
      '/sync',
      queryParameters: any(named: 'queryParameters'),
    ),
  ).thenAnswer(
    (_) async => Response(
      requestOptions: RequestOptions(path: '/sync'),
      data: data,
      statusCode: 200,
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  // =========================================================================
  // Test 1: pullDelta processes all 15 entity types (INFRA-04)
  // =========================================================================
  group('INFRA-04: pullDelta processes all 15 entity types', () {
    late AppDatabase db;
    late MockDioClient mockDioClient;
    late MockDio mockDio;
    late MockConnectivityService mockConnectivity;
    late SyncEngine engine;

    setUp(() {
      db = _openTestDb();
      mockDioClient = MockDioClient();
      mockDio = MockDio();
      mockConnectivity = MockConnectivityService();

      when(() => mockDioClient.instance).thenReturn(mockDio);

      final registry = _buildRegistry(db, mockDioClient);
      engine = SyncEngine(db, mockDioClient, registry, mockConnectivity);
    });

    tearDown(() async {
      engine.dispose();
      await db.close();
    });

    test('pullDelta persists all 15 entity types into Drift tables', () async {
      _stubSyncResponse(mockDio, _buildFullMockResponse());

      await engine.pullDelta();

      // companies
      expect(
        (await db.select(db.companies).get()).length,
        equals(1),
        reason: 'companies table should have 1 row',
      );
      // users
      expect(
        (await db.select(db.users).get()).length,
        equals(1),
        reason: 'users table should have 1 row',
      );
      // user_roles
      expect(
        (await db.select(db.userRoles).get()).length,
        equals(1),
        reason: 'userRoles table should have 1 row',
      );
      // jobs
      expect(
        (await db.select(db.jobs).get()).length,
        equals(1),
        reason: 'jobs table should have 1 row',
      );
      // bookings
      expect(
        (await db.select(db.bookings).get()).length,
        equals(1),
        reason: 'bookings table should have 1 row',
      );
      // job_sites
      expect(
        (await db.select(db.jobSites).get()).length,
        equals(1),
        reason: 'jobSites table should have 1 row',
      );
      // job_notes
      expect(
        (await db.select(db.jobNotes).get()).length,
        equals(1),
        reason: 'jobNotes table should have 1 row',
      );
      // time_entries
      expect(
        (await db.select(db.timeEntries).get()).length,
        equals(1),
        reason: 'timeEntries table should have 1 row',
      );
      // attachments
      expect(
        (await db.select(db.attachments).get()).length,
        equals(1),
        reason: 'attachments table should have 1 row',
      );
      // client_profiles
      expect(
        (await db.select(db.clientProfiles).get()).length,
        equals(1),
        reason: 'clientProfiles table should have 1 row',
      );
      // job_requests
      expect(
        (await db.select(db.jobRequests).get()).length,
        equals(1),
        reason: 'jobRequests table should have 1 row',
      );
      // quotes (upsertFromSync also upserts line_items via nested array)
      expect(
        (await db.select(db.quotes).get()).length,
        greaterThanOrEqualTo(1),
        reason: 'quotes table should have at least 1 row',
      );
      // quote_line_items (upserted by both QuoteSyncHandler nested AND QuoteLineItemSyncHandler flat)
      expect(
        (await db.select(db.quoteLineItems).get()).length,
        greaterThanOrEqualTo(1),
        reason: 'quoteLineItems table should have at least 1 row',
      );
      // invoices
      expect(
        (await db.select(db.invoices).get()).length,
        greaterThanOrEqualTo(1),
        reason: 'invoices table should have at least 1 row',
      );
      // invoice_line_items
      expect(
        (await db.select(db.invoiceLineItems).get()).length,
        greaterThanOrEqualTo(1),
        reason: 'invoiceLineItems table should have at least 1 row',
      );
    });
  });

  // =========================================================================
  // Test 2: JobSyncHandler maps GPS and FK fields (FIELD-02)
  // =========================================================================
  group('FIELD-02: JobSyncHandler maps GPS and FK fields', () {
    late AppDatabase db;
    late MockDioClient mockDioClient;
    late MockDio mockDio;
    late MockConnectivityService mockConnectivity;
    late SyncEngine engine;

    setUp(() {
      db = _openTestDb();
      mockDioClient = MockDioClient();
      mockDio = MockDio();
      mockConnectivity = MockConnectivityService();

      when(() => mockDioClient.instance).thenReturn(mockDio);

      final registry = _buildRegistry(db, mockDioClient);
      engine = SyncEngine(db, mockDioClient, registry, mockConnectivity);
    });

    tearDown(() async {
      engine.dispose();
      await db.close();
    });

    test('pullDelta maps gpsLatitude, gpsLongitude, gpsAddress, quoteId, invoiceId',
        () async {
      _stubSyncResponse(mockDio, _buildFullMockResponse());

      await engine.pullDelta();

      final jobs = await db.select(db.jobs).get();
      expect(jobs, hasLength(1));
      final job = jobs.first;

      expect(job.gpsLatitude, closeTo(37.7749, 0.001));
      expect(job.gpsLongitude, closeTo(-122.4194, 0.001));
      expect(job.gpsAddress, equals('123 Test St'));
      expect(job.quoteId, equals(_quoteId));
      expect(job.invoiceId, equals(_invoiceId));
    });

    test('gps_latitude as int (not double) is handled via is num check', () async {
      final data = _buildFullMockResponse();
      // Simulate server returning integer lat/lng (JSON int, not float)
      (data['jobs'] as List).first['gps_latitude'] = 37;
      (data['jobs'] as List).first['gps_longitude'] = -122;
      _stubSyncResponse(mockDio, data);

      await engine.pullDelta();

      final jobs = await db.select(db.jobs).get();
      expect(jobs, hasLength(1));
      expect(jobs.first.gpsLatitude, closeTo(37.0, 0.001));
      expect(jobs.first.gpsLongitude, closeTo(-122.0, 0.001));
    });
  });

  // =========================================================================
  // Test 3: Per-entity failure skips without aborting other types (INFRA-04)
  // =========================================================================
  group('INFRA-04: Per-entity failure skips without aborting', () {
    late AppDatabase db;
    late MockDioClient mockDioClient;
    late MockDio mockDio;
    late MockConnectivityService mockConnectivity;
    late SyncEngine engine;

    setUp(() {
      db = _openTestDb();
      mockDioClient = MockDioClient();
      mockDio = MockDio();
      mockConnectivity = MockConnectivityService();

      when(() => mockDioClient.instance).thenReturn(mockDio);

      final registry = _buildRegistry(db, mockDioClient);
      engine = SyncEngine(db, mockDioClient, registry, mockConnectivity);
    });

    tearDown(() async {
      engine.dispose();
      await db.close();
    });

    test(
        'invalid job entity skipped; companies and users still inserted; '
        'cursor updated', () async {
      final data = _buildFullMockResponse();
      // Corrupt the job entity: missing required 'id' field causes cast error
      (data['jobs'] as List)[0] = <String, dynamic>{
        'company_id': _companyId,
        // 'id' is intentionally missing — will cause a type cast error
        'description': 'Invalid job with no id',
        'trade_type': 'plumbing',
        'status': 'scheduled',
      };
      _stubSyncResponse(mockDio, data);

      // Should NOT throw despite invalid job
      await engine.pullDelta();

      // Companies and users should be persisted (other types not aborted)
      final companies = await db.select(db.companies).get();
      expect(companies, hasLength(1),
          reason: 'companies should be inserted despite job failure');

      final users = await db.select(db.users).get();
      expect(users, hasLength(1),
          reason: 'users should be inserted despite job failure');

      // Job should NOT be in Drift (it failed)
      final jobs = await db.select(db.jobs).get();
      expect(jobs, isEmpty,
          reason: 'invalid job should not be persisted');

      // Cursor should still be updated (processing completed despite error)
      final cursor = await db.syncCursorDao.getCursor();
      expect(cursor, isNotNull,
          reason: 'cursor should be updated even when individual entities fail');
    });
  });

  // =========================================================================
  // Test 4: Cursor updates after all types attempted (INFRA-04)
  // =========================================================================
  group('INFRA-04: Cursor updates to server_timestamp', () {
    late AppDatabase db;
    late MockDioClient mockDioClient;
    late MockDio mockDio;
    late MockConnectivityService mockConnectivity;
    late SyncEngine engine;

    setUp(() {
      db = _openTestDb();
      mockDioClient = MockDioClient();
      mockDio = MockDio();
      mockConnectivity = MockConnectivityService();

      when(() => mockDioClient.instance).thenReturn(mockDio);

      final registry = _buildRegistry(db, mockDioClient);
      engine = SyncEngine(db, mockDioClient, registry, mockConnectivity);
    });

    tearDown(() async {
      engine.dispose();
      await db.close();
    });

    test('cursor is null before pull, set to server_timestamp after', () async {
      _stubSyncResponse(mockDio, _buildFullMockResponse());

      // Cursor should be null before first pull
      expect(await db.syncCursorDao.getCursor(), isNull);

      await engine.pullDelta();

      final cursor = await db.syncCursorDao.getCursor();
      expect(cursor, isNotNull);

      // server_timestamp in mock is '2026-03-14T12:00:00Z'
      final expectedTimestamp = DateTime.utc(2026, 3, 14, 12);
      expect(
        cursor!.millisecondsSinceEpoch,
        equals(expectedTimestamp.millisecondsSinceEpoch),
      );
    });

    test('cursor updates on second pull with new server_timestamp', () async {
      // First pull
      _stubSyncResponse(mockDio, _buildFullMockResponse());
      await engine.pullDelta();

      final cursor1 = await db.syncCursorDao.getCursor();
      expect(cursor1, isNotNull);

      // Second pull with a later timestamp
      final data2 = {'server_timestamp': '2026-03-15T12:00:00Z'};
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/sync',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/sync'),
          data: data2,
          statusCode: 200,
        ),
      );

      await engine.pullDelta();

      final cursor2 = await db.syncCursorDao.getCursor();
      expect(cursor2, isNotNull);
      final expectedTs2 = DateTime.utc(2026, 3, 15, 12);
      expect(
        cursor2!.millisecondsSinceEpoch,
        equals(expectedTs2.millisecondsSinceEpoch),
      );
    });
  });

  // =========================================================================
  // Test 5: Booking cross-device propagation (SCHED-03)
  // =========================================================================
  group('SCHED-03: Booking cross-device propagation', () {
    late AppDatabase db;
    late MockDioClient mockDioClient;
    late MockDio mockDio;
    late MockConnectivityService mockConnectivity;
    late SyncEngine engine;

    setUp(() {
      db = _openTestDb();
      mockDioClient = MockDioClient();
      mockDio = MockDio();
      mockConnectivity = MockConnectivityService();

      when(() => mockDioClient.instance).thenReturn(mockDio);

      final registry = _buildRegistry(db, mockDioClient);
      engine = SyncEngine(db, mockDioClient, registry, mockConnectivity);
    });

    tearDown(() async {
      engine.dispose();
      await db.close();
    });

    test('booking from sync response is persisted with correct fields', () async {
      _stubSyncResponse(mockDio, _buildFullMockResponse());

      await engine.pullDelta();

      final bookings = await db.select(db.bookings).get();
      expect(bookings, hasLength(1));

      final booking = bookings.first;
      expect(booking.id, equals(_bookingId));
      expect(booking.contractorId, equals(_userId));
      expect(booking.jobId, equals(_jobId));
      expect(booking.companyId, equals(_companyId));

      // Time range should be parsed correctly
      expect(booking.timeRangeStart, isNotNull);
      expect(booking.timeRangeEnd, isNotNull);
      final expectedStart = DateTime.utc(2026, 3, 14, 8);
      expect(
        booking.timeRangeStart.millisecondsSinceEpoch,
        equals(expectedStart.millisecondsSinceEpoch),
      );
    });

    test('soft-deleted booking tombstone is propagated', () async {
      final data = _buildFullMockResponse();
      (data['bookings'] as List).first['deleted_at'] = '2026-03-14T09:00:00Z';
      _stubSyncResponse(mockDio, data);

      await engine.pullDelta();

      final bookings = await db.select(db.bookings).get();
      expect(bookings, hasLength(1));
      expect(bookings.first.deletedAt, isNotNull);
    });
  });

  // =========================================================================
  // Test 6: Quote/Invoice cross-device propagation (BIZ-01, BIZ-03)
  // =========================================================================
  group('BIZ-01 + BIZ-03: Quote/Invoice cross-device propagation', () {
    late AppDatabase db;
    late MockDioClient mockDioClient;
    late MockDio mockDio;
    late MockConnectivityService mockConnectivity;
    late SyncEngine engine;

    setUp(() {
      db = _openTestDb();
      mockDioClient = MockDioClient();
      mockDio = MockDio();
      mockConnectivity = MockConnectivityService();

      when(() => mockDioClient.instance).thenReturn(mockDio);

      final registry = _buildRegistry(db, mockDioClient);
      engine = SyncEngine(db, mockDioClient, registry, mockConnectivity);
    });

    tearDown(() async {
      engine.dispose();
      await db.close();
    });

    test('quote and quote_line_items are persisted with correct FKs', () async {
      _stubSyncResponse(mockDio, _buildFullMockResponse());

      await engine.pullDelta();

      final quotes = await db.select(db.quotes).get();
      expect(quotes.length, greaterThanOrEqualTo(1), reason: 'quotes should be present');

      final quoteRow = quotes.first;
      expect(quoteRow.id, equals(_quoteId));
      expect(quoteRow.jobId, equals(_jobId));
      expect(quoteRow.companyId, equals(_companyId));

      final lineItems = await db.select(db.quoteLineItems).get();
      expect(lineItems.length, greaterThanOrEqualTo(1),
          reason: 'quote line items should be present');

      // All line items should reference the parent quote
      for (final item in lineItems) {
        expect(item.quoteId, equals(_quoteId));
      }
    });

    test('invoice and invoice_line_items are persisted with correct FKs',
        () async {
      _stubSyncResponse(mockDio, _buildFullMockResponse());

      await engine.pullDelta();

      final invoices = await db.select(db.invoices).get();
      expect(invoices.length, greaterThanOrEqualTo(1),
          reason: 'invoices should be present');

      final invoiceRow = invoices.first;
      expect(invoiceRow.id, equals(_invoiceId));
      expect(invoiceRow.jobId, equals(_jobId));
      expect(invoiceRow.companyId, equals(_companyId));

      final lineItems = await db.select(db.invoiceLineItems).get();
      expect(lineItems.length, greaterThanOrEqualTo(1));

      // All line items should reference the parent invoice
      for (final item in lineItems) {
        expect(item.invoiceId, equals(_invoiceId));
      }
    });

    test('quote_line_items flat array populates quoteLineItems table', () async {
      _stubSyncResponse(mockDio, _buildFullMockResponse());

      await engine.pullDelta();

      final lineItems = await db.select(db.quoteLineItems).get();
      expect(lineItems.length, greaterThanOrEqualTo(1));

      // Verify flat line item fields
      final item = lineItems.firstWhere((li) => li.id == _quoteLineItemId,
          orElse: () => throw StateError('Quote line item $_quoteLineItemId not found'));
      expect(item.description, equals('Labour charge'));
      expect(item.quantity, closeTo(2.0, 0.001));
      expect(item.unitPrice, closeTo(100.0, 0.001));
    });

    test('invoice_line_items flat array populates invoiceLineItems table',
        () async {
      _stubSyncResponse(mockDio, _buildFullMockResponse());

      await engine.pullDelta();

      final lineItems = await db.select(db.invoiceLineItems).get();
      expect(lineItems.length, greaterThanOrEqualTo(1));

      final item = lineItems.firstWhere((li) => li.id == _invoiceLineItemId,
          orElse: () => throw StateError('Invoice line item $_invoiceLineItemId not found'));
      expect(item.description, equals('Labour charge'));
      expect(item.quantity, closeTo(2.0, 0.001));
      expect(item.unitPrice, closeTo(100.0, 0.001));
    });
  });
}
