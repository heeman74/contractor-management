// Widget test for the client-side change-order review: QuoteDetailScreen renders
// change-order context (CO-N + reason + schedule impact) for a change order.
//
// (The "list a job's change orders" surfacing logic is covered reliably at the
// DAO level in test/features/quotes/change_order_dao_test.dart via
// watchChangeOrdersForOriginatingJob; the section UI is analyzer-verified.)

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/quotes/presentation/providers/quote_providers.dart';
import 'package:contractorhub/features/quotes/presentation/screens/quote_detail_screen.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _openDb() => AppDatabase(NativeDatabase.memory());

/// Unmount the tree before the DB closes. `quoteByIdProvider` is a
/// StreamProvider over the DAO, so a still-mounted scope keeps a drift
/// subscription open and `db.close()` waits on it forever — the repo-wide
/// idiom (see jobs_pipeline_screen_test.dart).
Future<void> _cleanup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

Future<void> _seedCompany(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          id: const Value('company-001'),
          name: 'Ace Co',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Map<String, dynamic> _coPayload({
  required String id,
  required int coNumber,
  String status = 'sent',
}) =>
    {
      'id': id,
      'company_id': 'company-001',
      'job_id': null,
      'quote_kind': 'change_order',
      'co_number': coNumber,
      'change_reason': 'Rotted subfloor found under tile',
      'schedule_impact_days': 3,
      'project_id': 'proj-1',
      'originating_job_id': 'job-1',
      'co_target': 'new_job',
      'status': status,
      'revision_number': 1,
      'tax_rate': 0,
      'discount_value': 0,
      'created_at': '2026-07-30T00:00:00Z',
      'updated_at': '2026-07-30T00:00:00Z',
      'line_items': [
        {
          'id': 'li-$id',
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
    };

void main() {
  late AppDatabase db;

  setUp(() async {
    db = _openDb();
    await _seedCompany(db);
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('quote detail shows change-order context', (tester) async {
    // 'viewed' so the detail's sent-only view receipt (a dio call) is skipped.
    await db.quoteDao.upsertFromSync(
      _coPayload(id: 'co-1', coNumber: 2, status: 'viewed'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [quoteDaoProvider.overrideWithValue(db.quoteDao)],
        child: const MaterialApp(home: QuoteDetailScreen(quoteId: 'co-1')),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    expect(find.text('Change Order CO-2'), findsWidgets);
    expect(find.textContaining('Rotted subfloor'), findsWidgets);
    expect(find.textContaining('Schedule impact: +3 days'), findsOneWidget);

    await _cleanup(tester);
  });
}
