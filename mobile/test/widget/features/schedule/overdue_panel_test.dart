/// Widget tests for OverduePanel — UAT #14.
///
/// Tests cover:
/// 1. Panel hidden when showOverduePanelProvider is false
/// 2. Panel visible when showOverduePanelProvider is true
/// 3. Empty state "No overdue jobs" with check icon
/// 4. Overdue job list shows job description
/// 5. Days overdue badge renders (e.g., "3d overdue")
/// 6. Severity chip shows CRITICAL/WARNING text
/// 7. Delay reason displayed when hasDelayReport is true
/// 8. Action buttons: "View job" and "Contact contractor" tooltips
///
/// Strategy: OverduePanel is a ConsumerWidget watching showOverduePanelProvider
/// and overdueJobsProvider. Override both with test values.
library;

import 'package:contractorhub/features/schedule/domain/overdue_service.dart';
import 'package:contractorhub/features/schedule/presentation/providers/calendar_providers.dart';
import 'package:contractorhub/features/schedule/presentation/providers/overdue_providers.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/overdue_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Widget buildOverduePanel({
  bool isVisible = true,
  List<OverdueJobInfo> overdueJobs = const [],
}) {
  return ProviderScope(
    overrides: [
      showOverduePanelProvider.overrideWith((ref) => isVisible),
      overdueJobsProvider.overrideWithValue(overdueJobs),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            OverduePanel(),
          ],
        ),
      ),
    ),
  );
}

OverdueJobInfo makeOverdueInfo({
  String jobId = 'job-1',
  String description = 'Fix leaking roof',
  int daysOverdue = 3,
  OverdueSeverity severity = OverdueSeverity.warning,
  bool hasDelayReport = false,
  String? latestDelayReason,
  String? contractorName,
}) {
  return OverdueJobInfo(
    jobId: jobId,
    description: description,
    scheduledCompletionDate: DateTime.now().subtract(
      Duration(days: daysOverdue),
    ),
    daysOverdue: daysOverdue,
    severity: severity,
    hasDelayReport: hasDelayReport,
    latestDelayReason: latestDelayReason,
    contractorName: contractorName,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('OverduePanel — UAT #14', () {
    testWidgets('panel not visible when showOverduePanelProvider is false',
        (tester) async {
      await tester.pumpWidget(buildOverduePanel(isVisible: false));
      await tester.pumpAndSettle();

      // Panel has zero height when hidden — content should not be visible
      expect(find.text('No overdue jobs'), findsNothing);
    });

    testWidgets('empty state shows "No overdue jobs" with check icon',
        (tester) async {
      await tester.pumpWidget(buildOverduePanel(
        isVisible: true,
        overdueJobs: [],
      ));
      await tester.pumpAndSettle();

      expect(find.text('No overdue jobs'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('panel header shows count of overdue jobs', (tester) async {
      await tester.pumpWidget(buildOverduePanel(
        isVisible: true,
        overdueJobs: [
          makeOverdueInfo(jobId: 'j1', description: 'Job A'),
          makeOverdueInfo(jobId: 'j2', description: 'Job B'),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('2 overdue jobs'), findsOneWidget);
    });

    testWidgets('single overdue job uses singular "job"', (tester) async {
      await tester.pumpWidget(buildOverduePanel(
        isVisible: true,
        overdueJobs: [makeOverdueInfo()],
      ));
      await tester.pumpAndSettle();

      expect(find.text('1 overdue job'), findsOneWidget);
    });

    testWidgets('overdue job description is displayed', (tester) async {
      await tester.pumpWidget(buildOverduePanel(
        isVisible: true,
        overdueJobs: [
          makeOverdueInfo(description: 'Replace gutters on north side'),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Replace gutters on north side'), findsOneWidget);
    });

    testWidgets('days overdue badge renders correctly', (tester) async {
      await tester.pumpWidget(buildOverduePanel(
        isVisible: true,
        overdueJobs: [makeOverdueInfo(daysOverdue: 5)],
      ));
      await tester.pumpAndSettle();

      expect(find.text('5d overdue'), findsOneWidget);
    });

    testWidgets('CRITICAL severity chip displayed', (tester) async {
      await tester.pumpWidget(buildOverduePanel(
        isVisible: true,
        overdueJobs: [
          makeOverdueInfo(severity: OverdueSeverity.critical, daysOverdue: 7),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('CRITICAL'), findsOneWidget);
    });

    testWidgets('WARNING severity chip displayed', (tester) async {
      await tester.pumpWidget(buildOverduePanel(
        isVisible: true,
        overdueJobs: [
          makeOverdueInfo(severity: OverdueSeverity.warning, daysOverdue: 2),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('WARNING'), findsOneWidget);
    });

    testWidgets('delay reason shown when hasDelayReport is true',
        (tester) async {
      await tester.pumpWidget(buildOverduePanel(
        isVisible: true,
        overdueJobs: [
          makeOverdueInfo(
            hasDelayReport: true,
            latestDelayReason: 'Parts on backorder',
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Delay: Parts on backorder'), findsOneWidget);
      expect(find.byIcon(Icons.schedule_send_outlined), findsOneWidget);
    });

    testWidgets('action buttons have correct tooltips', (tester) async {
      await tester.pumpWidget(buildOverduePanel(
        isVisible: true,
        overdueJobs: [makeOverdueInfo()],
      ));
      await tester.pumpAndSettle();

      expect(find.byTooltip('View job'), findsOneWidget);
      expect(find.byTooltip('Contact contractor'), findsOneWidget);
    });

    testWidgets('header shows warning icon', (tester) async {
      await tester.pumpWidget(buildOverduePanel(
        isVisible: true,
        overdueJobs: [makeOverdueInfo()],
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('contractor name displayed when available', (tester) async {
      await tester.pumpWidget(buildOverduePanel(
        isVisible: true,
        overdueJobs: [
          makeOverdueInfo(contractorName: 'contractor-42'),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('contractor-42'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });
  });
}
