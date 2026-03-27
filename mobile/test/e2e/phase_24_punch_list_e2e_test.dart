// Phase 24 — GC Inspection Workflow: Flutter E2E tests — INSP-03.
//
// Covers punch list item rendering via PunchListCard widget:
//   INSP-03-01: PunchListCard renders item description
//   INSP-03-02: PunchListCard shows Punch badge (orange chip)
//   INSP-03-03: PunchListCard renders priority chip
//   INSP-03-04: PunchListCard renders status chip with correct text
//   INSP-03-05: PunchListCard shows due date when set
//   INSP-03-06: PunchListCard does not show due date when null
//   INSP-03-07: urgent priority chip color is red (0xFFD32F2F)
//   INSP-03-08: open status chip renders as "open"
//   INSP-03-09: in_progress status chip renders as "in progress"
//   INSP-03-10: resolved status chip renders as "resolved"
//   INSP-03-11: verified status chip renders as "verified"
//   INSP-03-12: Multiple cards in a list all render descriptions
//
// Patterns:
//   - PunchListCard is a pure StatelessWidget — no providers needed
//   - pump() NOT pumpAndSettle() — consistent with project test patterns
//   - No GetIt initialization needed for widget-only tests

import 'package:contractorhub/core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;
import 'package:contractorhub/features/projects/presentation/widgets/punch_list_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const _companyId = 'company-001';
const _projectId = 'project-001';
const _scopeId = 'scope-001';
const _userId = 'user-001';

// ---------------------------------------------------------------------------
// Data builder helpers
// ---------------------------------------------------------------------------

PunchListItem _makeItem({
  String id = 'item-001',
  String description = 'Fix outlet',
  String priority = 'medium',
  String status = 'open',
  String? sourceFlagId,
  DateTime? dueDate,
}) {
  final now = DateTime.now();
  return PunchListItem(
    id: id,
    companyId: _companyId,
    projectId: _projectId,
    tradeScopeId: _scopeId,
    createdBy: _userId,
    description: description,
    priority: priority,
    status: status,
    sourceFlagId: sourceFlagId,
    dueDate: dueDate,
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

// ---------------------------------------------------------------------------
// Widget wrapper helper
// ---------------------------------------------------------------------------

Widget _wrapCard(PunchListItem item, {VoidCallback? onTap}) {
  return MaterialApp(
    home: Scaffold(
      body: PunchListCard(item: item, onTap: onTap),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PunchListCard rendering', () {
    testWidgets('renders item description', (tester) async {
      final item = _makeItem(description: 'Fix leaking pipe');

      await tester.pumpWidget(_wrapCard(item));
      await tester.pump();

      expect(find.text('Fix leaking pipe'), findsOneWidget);
    });

    testWidgets('shows Punch badge', (tester) async {
      final item = _makeItem();

      await tester.pumpWidget(_wrapCard(item));
      await tester.pump();

      expect(find.text('Punch'), findsOneWidget);
    });

    testWidgets('renders priority chip text', (tester) async {
      final item = _makeItem(priority: 'high');

      await tester.pumpWidget(_wrapCard(item));
      await tester.pump();

      expect(find.text('high'), findsOneWidget);
    });

    testWidgets('renders urgent priority chip', (tester) async {
      final item = _makeItem(priority: 'urgent');

      await tester.pumpWidget(_wrapCard(item));
      await tester.pump();

      expect(find.text('urgent'), findsOneWidget);
    });

    testWidgets('renders low priority chip', (tester) async {
      final item = _makeItem(priority: 'low');

      await tester.pumpWidget(_wrapCard(item));
      await tester.pump();

      expect(find.text('low'), findsOneWidget);
    });

    testWidgets('shows open status chip as "open"', (tester) async {
      final item = _makeItem();

      await tester.pumpWidget(_wrapCard(item));
      await tester.pump();

      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('shows in_progress status chip as "in progress"', (tester) async {
      final item = _makeItem(status: 'in_progress');

      await tester.pumpWidget(_wrapCard(item));
      await tester.pump();

      expect(find.text('in progress'), findsOneWidget);
    });

    testWidgets('shows resolved status chip as "resolved"', (tester) async {
      final item = _makeItem(status: 'resolved');

      await tester.pumpWidget(_wrapCard(item));
      await tester.pump();

      expect(find.text('resolved'), findsOneWidget);
    });

    testWidgets('shows verified status chip as "verified"', (tester) async {
      final item = _makeItem(status: 'verified');

      await tester.pumpWidget(_wrapCard(item));
      await tester.pump();

      expect(find.text('verified'), findsOneWidget);
    });

    testWidgets('shows due date when set', (tester) async {
      final dueDate = DateTime(2025, 6, 15);
      final item = _makeItem(dueDate: dueDate);

      await tester.pumpWidget(_wrapCard(item));
      await tester.pump();

      expect(find.textContaining('Jun 15, 2025'), findsOneWidget);
    });

    testWidgets('does not show due date when null', (tester) async {
      final item = _makeItem();

      await tester.pumpWidget(_wrapCard(item));
      await tester.pump();

      expect(find.textContaining('Due:'), findsNothing);
    });

    testWidgets('onTap callback fires when tapped', (tester) async {
      bool tapped = false;
      final item = _makeItem();

      await tester.pumpWidget(
        _wrapCard(item, onTap: () => tapped = true),
      );
      await tester.pump();

      await tester.tap(find.byType(PunchListCard));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });

  group('PunchListCard list rendering', () {
    testWidgets('multiple cards in a column all render descriptions',
        (tester) async {
      final items = [
        _makeItem(id: 'i1'),
        _makeItem(id: 'i2', description: 'Repair drywall'),
        _makeItem(id: 'i3', description: 'Replace tile'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: items
                  .map((item) => PunchListCard(item: item))
                  .toList(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Fix outlet'), findsOneWidget);
      expect(find.text('Repair drywall'), findsOneWidget);
      expect(find.text('Replace tile'), findsOneWidget);
    });

    testWidgets('items have orange left edge container', (tester) async {
      final item = _makeItem();

      await tester.pumpWidget(_wrapCard(item));
      await tester.pump();

      // Check that the deep orange (0xFFE65100) container exists
      final container = tester.widgetList<Container>(find.byType(Container));
      final hasOrangeEdge = container.any((c) =>
          c.color == const Color(0xFFE65100) ||
          (c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color ==
                  const Color(0xFFE65100)));
      expect(hasOrangeEdge, isTrue,
          reason: 'Punch list card should have deep orange left edge');
    });
  });

  group('PunchListCard priority chip colors', () {
    testWidgets('urgent priority chip has red background', (tester) async {
      final item = _makeItem(priority: 'urgent');

      await tester.pumpWidget(_wrapCard(item));
      await tester.pump();

      // Find all chips and check the priority chip color
      final chips = tester.widgetList<Chip>(find.byType(Chip)).toList();
      final priorityChip = chips.firstWhere(
        (c) {
          final label = c.label;
          return label is Text && (label).data == 'urgent';
        },
      );
      expect(priorityChip.backgroundColor, equals(const Color(0xFFD32F2F)));
    });

    testWidgets('high priority chip has orange background', (tester) async {
      final item = _makeItem(priority: 'high');

      await tester.pumpWidget(_wrapCard(item));
      await tester.pump();

      final chips = tester.widgetList<Chip>(find.byType(Chip)).toList();
      final priorityChip = chips.firstWhere(
        (c) {
          final label = c.label;
          return label is Text && (label).data == 'high';
        },
      );
      expect(priorityChip.backgroundColor, equals(const Color(0xFFF57C00)));
    });
  });
}
