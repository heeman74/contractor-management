// Contractor Availability — Flutter E2E widget tests.
//
// Target: lib/features/contractor/presentation/screens/availability_screen.dart
//
// ─── SOURCE REALITY (read the file — it overrides the naive spec) ──────────
//   AvailabilityScreen is a Phase-3 PLACEHOLDER. As shipped it is a plain
//   `StatelessWidget` whose sole `import` is `package:flutter/material.dart`.
//   It renders a static "Coming in Phase 3" card:
//     - AppBar title "My Availability"
//     - an `Icons.event_available_outlined` glyph
//     - a bold "Availability" heading
//     - the sub-label "Contractor Only — Coming in Phase 3"
//     - descriptive body copy about setting hours / blocking time off
//
//   Critically, the screen (and the whole codebase) has NO availability data
//   model. A repo-wide search found NO availability/working-hours/time-off/
//   blocked-date Drift table, DAO, repository, service, provider, or notifier.
//   The doc comment promises "recurring weekly hours", "block dates",
//   "scheduling integration" — none of that is implemented yet.
//
//   Consequences for this E2E suite (honest to the source):
//     * There is NOTHING to SET / TOGGLE / EDIT / REMOVE — no interactive
//       control exists, so the "set availability", "edit entry", "remove entry"
//       and "validation (end-before-start)" flows requested by the spec cannot
//       be written against this screen. They will land when Phase 3 ships.
//     * There is NO write path — neither offline-first Drift + sync_queue nor a
//       Dio request — so there is nothing to assert on the DB / sync-queue /
//       captured HTTP payload, and no MockDioClient is required.
//     * The screen resolves NOTHING from getIt<...>() and reads NO Riverpod
//       provider, so per harness rule 1 no AppDatabase is registered. Per rule
//       2 the ProviderScope still overrides authNotifierProvider with a fake
//       contractor AuthNotifier to pin the actor context (the contractor is who
//       this screen is gated to); the override is currently inert because the
//       placeholder never reads auth, but it documents the intended actor and
//       future-proofs the harness for when Phase 3 wires providers in.
//
//   This file therefore verifies what the screen ACTUALLY does today: it renders
//   the placeholder correctly and stably under the contractor actor, needs no
//   backing data (its natural "empty" state), and survives its full mount →
//   render → unmount lifecycle without leaking timers. When Phase 3 implements
//   the real availability UI + data layer, extend this suite with the
//   set/toggle/edit/remove/validate/error flows against the new source.
//
// Harness rules (CLAUDE.md + MEMORY.md):
//   * pump() / pump(Duration(...)) only — never pumpAndSettle.
//   * ProviderScope overrides authNotifierProvider with a fake AuthNotifier
//     exposing AuthState.authenticated(roles: {UserRole.contractor}).
//   * Unmount to SizedBox + pump at each test end to drain any pending timers.

import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/contractor/presentation/screens/availability_screen.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _contractorUserId = 'contractor-001';
const _companyId = 'company-001';

// ---------------------------------------------------------------------------
// Auth state helper — the contractor is the actor this screen is gated to.
// ---------------------------------------------------------------------------

AuthState _contractorAuth() => const AuthState.authenticated(
      userId: _contractorUserId,
      companyId: _companyId,
      roles: {UserRole.contractor},
    );

// ---------------------------------------------------------------------------
// Fake AuthNotifier — supplies a fixed AuthState without hitting
// getIt<AuthRepository>(). Fake AsyncNotifiers extend the real notifier class.
// ---------------------------------------------------------------------------

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._state);

  final AuthState _state;

  @override
  AuthState build() => _state;
}

// ---------------------------------------------------------------------------
// Widget pump helper
// ---------------------------------------------------------------------------

Future<void> _pumpScreen(
  WidgetTester tester, {
  required AuthState auth,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      ],
      child: const MaterialApp(home: AvailabilityScreen()),
    ),
  );
  // Static screen: a single frame is enough. NO pumpAndSettle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Unmount the tree and flush any pending zero-duration timers scheduled during
/// disposal (MEMORY.md: never leave a pending Timer after the tree is gone).
/// Call at the END of every test that mounts the real screen.
Future<void> _drainTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('AvailabilityScreen E2E (Phase-3 placeholder)', () {
    // ─── 1: renders the placeholder availability UI ────────────────────────
    testWidgets('renders the availability placeholder card for a contractor',
        (tester) async {
      await _pumpScreen(tester, auth: _contractorAuth());

      // AppBar title.
      expect(find.text('My Availability'), findsOneWidget);

      // The availability glyph.
      expect(find.byIcon(Icons.event_available_outlined), findsOneWidget);

      // Bold heading + role-scoped sub-label.
      expect(find.text('Availability'), findsOneWidget);
      expect(find.text('Contractor Only — Coming in Phase 3'), findsOneWidget);

      // Descriptive body copy (the promised feature set).
      expect(
        find.text(
          'Set your working hours, block time off,\n'
          'and manage trade availability.',
        ),
        findsOneWidget,
      );

      await _drainTimers(tester);
    });

    // ─── 2: natural empty state — no backing data required ─────────────────
    testWidgets(
        'renders with no seeded availability data (its natural empty state)',
        (tester) async {
      // No AppDatabase is registered and no availability rows exist anywhere —
      // the placeholder must still render cleanly with zero backing data.
      await _pumpScreen(tester, auth: _contractorAuth());

      expect(find.byType(AvailabilityScreen), findsOneWidget);
      expect(find.text('Availability'), findsOneWidget);
      // No list / calendar / toggle controls exist to populate yet.
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(TextField), findsNothing);

      await _drainTimers(tester);
    });

    // ─── 3: no interactive availability controls exist yet ─────────────────
    testWidgets(
        'exposes no set/toggle/edit controls (nothing to write in Phase-3 '
        'placeholder)', (tester) async {
      await _pumpScreen(tester, auth: _contractorAuth());

      // The set/toggle/edit/remove flows the spec asks for require controls
      // that Phase 3 has not built. Assert their absence so this test starts
      // failing (a useful signal) the moment real controls are introduced.
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(Switch), findsNothing);

      await _drainTimers(tester);
    });

    // ─── 4: lifecycle stability — mount → render → unmount, no leaks ────────
    testWidgets('mounts and unmounts cleanly without leaking timers',
        (tester) async {
      await _pumpScreen(tester, auth: _contractorAuth());
      expect(find.byType(AvailabilityScreen), findsOneWidget);

      // Explicit unmount; _drainTimers asserts no pending timer survives.
      await _drainTimers(tester);

      expect(find.byType(AvailabilityScreen), findsNothing);
    });
  });
}
