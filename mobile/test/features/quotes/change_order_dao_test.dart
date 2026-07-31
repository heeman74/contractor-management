// Drift DAO tests for the change-order fields on QuoteDao.
//
// Covers:
//   - upsertFromSync maps the change-order columns from a pulled payload, and
//     the row → QuoteEntity mapping exposes them (isChangeOrder, coNumber, …).
//   - createQuote enqueues a CREATE sync payload carrying the change-order
//     fields (quote_kind, project_id, originating_job_id, co_target).
//
// Patterns: NativeDatabase.memory(); seed Company (FK for quotes.company_id).

import 'dart:convert';

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/quotes/domain/quote_entity.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _companyId = 'company-co-001';

AppDatabase _openDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedCompany(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          id: const Value(_companyId),
          name: 'Test Company',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = _openDb();
    await _seedCompany(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('upsertFromSync maps change-order fields and the entity exposes them', () async {
    await db.quoteDao.upsertFromSync({
      'id': 'co-quote-1',
      'company_id': _companyId,
      'job_id': null,
      'quote_kind': 'change_order',
      'co_number': 3,
      'change_reason': 'Rotted subfloor found',
      'schedule_impact_days': 5,
      'project_id': 'proj-1',
      'originating_job_id': 'job-1',
      'co_target': 'new_job',
      'created_job_id': 'job-new',
      'status': 'sent',
      'revision_number': 1,
      'tax_rate': 0,
      'discount_value': 0,
      'created_at': '2026-07-30T00:00:00Z',
      'updated_at': '2026-07-30T00:00:00Z',
      'line_items': [
        {
          'id': 'li-1',
          'item_type': 'labor',
          'description': 'Replace subfloor',
          'quantity': 8,
          'unit': 'hr',
          'unit_price': 80,
          'sort_order': 0,
          'created_at': '2026-07-30T00:00:00Z',
          'updated_at': '2026-07-30T00:00:00Z',
        },
      ],
    });

    final quote = await db.quoteDao.watchQuote('co-quote-1').first;
    expect(quote, isNotNull);
    expect(quote!.isChangeOrder, isTrue);
    expect(quote.coNumber, 3);
    expect(quote.changeReason, 'Rotted subfloor found');
    expect(quote.scheduleImpactDays, 5);
    expect(quote.projectId, 'proj-1');
    expect(quote.originatingJobId, 'job-1');
    expect(quote.coTarget, 'new_job');
    expect(quote.createdJobId, 'job-new');
    expect(quote.lineItems, hasLength(1));
  });

  test('createQuote enqueues a CREATE payload carrying the change-order fields', () async {
    final now = DateTime.now();
    final entity = QuoteEntity(
      id: 'local-co-1',
      companyId: _companyId,
      status: 'draft',
      revisionNumber: 1,
      taxRate: 0,
      discountValue: 0,
      lineItems: const [],
      quoteKind: 'change_order',
      projectId: 'proj-1',
      originatingJobId: 'job-1',
      coTarget: 'existing_job',
      changeReason: 'Added scope',
      scheduleImpactDays: 2,
      createdAt: now,
      updatedAt: now,
    );
    await db.quoteDao.createQuote(entity);

    final queued = await db.select(db.syncQueue).get();
    final createItem = queued.firstWhere(
      (q) => q.entityType == 'quote' && q.operation == 'CREATE',
    );
    final payload = jsonDecode(createItem.payload) as Map<String, dynamic>;
    expect(payload['quote_kind'], 'change_order');
    expect(payload['project_id'], 'proj-1');
    expect(payload['originating_job_id'], 'job-1');
    expect(payload['co_target'], 'existing_job');
    expect(payload['change_reason'], 'Added scope');
    expect(payload['schedule_impact_days'], 2);
  });

  test('watchChangeOrdersForOriginatingJob streams a job\'s change orders by CO number',
      () async {
    // A standard job quote (not a change order) — must NOT appear.
    await db.quoteDao.upsertFromSync({
      'id': 'q-standard',
      'company_id': _companyId,
      'job_id': 'job-1',
      'status': 'sent',
      'revision_number': 1,
      'tax_rate': 0,
      'discount_value': 0,
      'created_at': '2026-07-30T00:00:00Z',
      'updated_at': '2026-07-30T00:00:00Z',
      'line_items': [],
    });
    // Two change orders on job-1 (out of CO order) + one on another job.
    for (final co in [
      ('co-2', 2, 'job-1'),
      ('co-1', 1, 'job-1'),
      ('co-other', 1, 'job-9'),
    ]) {
      await db.quoteDao.upsertFromSync({
        'id': co.$1,
        'company_id': _companyId,
        'job_id': null,
        'quote_kind': 'change_order',
        'co_number': co.$2,
        'originating_job_id': co.$3,
        'co_target': 'new_job',
        'status': 'sent',
        'revision_number': 1,
        'tax_rate': 0,
        'discount_value': 0,
        'created_at': '2026-07-30T00:00:00Z',
        'updated_at': '2026-07-30T00:00:00Z',
        'line_items': [],
      });
    }

    final changeOrders =
        await db.quoteDao.watchChangeOrdersForOriginatingJob('job-1').first;
    // Only job-1's change orders, ordered by CO number — no standard quote,
    // no other job's change order.
    expect(changeOrders.map((c) => c.id).toList(), ['co-1', 'co-2']);
    expect(changeOrders.every((c) => c.isChangeOrder), isTrue);
  });
}
