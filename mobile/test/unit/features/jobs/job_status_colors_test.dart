/// Unit tests for [JobStatusColors] — the shared JobStatus→Color mappings that
/// replaced five duplicated switch statements across job screens/cards.
library;

import 'package:contractorhub/features/jobs/domain/job_status.dart';
import 'package:contractorhub/features/jobs/domain/job_status_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JobStatusColors.detail', () {
    test('maps each status to the detail palette', () {
      expect(JobStatusColors.detail(JobStatus.quote), Colors.grey);
      expect(JobStatusColors.detail(JobStatus.scheduled), Colors.blue);
      expect(JobStatusColors.detail(JobStatus.inProgress), Colors.orange);
      expect(JobStatusColors.detail(JobStatus.complete), Colors.green);
      expect(JobStatusColors.detail(JobStatus.invoiced), Colors.purple);
      expect(JobStatusColors.detail(JobStatus.cancelled), Colors.red);
    });
  });

  group('JobStatusColors.pipeline', () {
    test('maps each status to the kanban palette', () {
      expect(JobStatusColors.pipeline(JobStatus.quote), Colors.blue);
      expect(JobStatusColors.pipeline(JobStatus.scheduled), Colors.orange);
      expect(JobStatusColors.pipeline(JobStatus.inProgress), Colors.amber[700]);
      expect(JobStatusColors.pipeline(JobStatus.complete), Colors.green);
      expect(JobStatusColors.pipeline(JobStatus.invoiced), Colors.purple);
      expect(JobStatusColors.pipeline(JobStatus.cancelled), Colors.grey);
    });
  });

  test('detail and pipeline palettes differ for quote', () {
    expect(
      JobStatusColors.detail(JobStatus.quote),
      isNot(JobStatusColors.pipeline(JobStatus.quote)),
    );
  });
}
