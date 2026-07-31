// E2E widget test for the contractor change-order builder.
//
// Drives the full flow: fill reason + line item → tap save → QuoteDao.createQuote
// → persisted to a real in-memory Drift DB as a change_order quote with the
// project/originating-job/target context, and a CREATE sync item enqueued.

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/quotes/presentation/providers/quote_providers.dart';
import 'package:contractorhub/features/quotes/presentation/screens/change_order_builder_screen.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeAuthNotifier extends AuthNotifier {
  final AuthState _state;
  _FakeAuthNotifier(this._state);
  @override
  AuthState build() => _state;
}

AppDatabase _openDb() => AppDatabase(NativeDatabase.memory());

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

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: SizedBox())),
        GoRoute(
          path: '/co',
          builder: (_, __) => const ChangeOrderBuilderScreen(
            projectId: 'proj-1',
            originatingJobId: 'job-1',
          ),
        ),
      ],
    );

void main() {
  late AppDatabase db;

  setUp(() async {
    db = _openDb();
    await _seedCompany(db);
  });

  tearDown(() async => db.close());

  testWidgets('saving a change order persists it as a change_order quote', (tester) async {
    final router = _router();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(
              const AuthState.authenticated(
                userId: 'u1',
                companyId: 'company-001',
                roles: {UserRole.contractor},
              ),
            ),
          ),
          quoteDaoProvider.overrideWithValue(db.quoteDao),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    router.push('/co');
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('co_reason')), 'Rotted subfloor found');
    await tester.enterText(find.byKey(const Key('co_line_desc_0')), 'Replace subfloor');
    await tester.enterText(find.byKey(const Key('co_line_price_0')), '80');
    await tester.pump();

    await tester.tap(find.byKey(const Key('save_change_order')));
    await tester.pumpAndSettle();

    final quotes = await db.select(db.quotes).get();
    expect(quotes, hasLength(1));
    final co = quotes.single;
    expect(co.quoteKind, 'change_order');
    expect(co.projectId, 'proj-1');
    expect(co.originatingJobId, 'job-1');
    expect(co.coTarget, 'new_job');
    expect(co.changeReason, 'Rotted subfloor found');

    // A CREATE sync item was enqueued for the change order.
    final queued = await db.select(db.syncQueue).get();
    expect(
      queued.where((q) => q.entityType == 'quote' && q.operation == 'CREATE'),
      hasLength(1),
    );
  });
}
