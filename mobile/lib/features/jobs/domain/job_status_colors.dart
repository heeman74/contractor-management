import 'package:flutter/material.dart';

import 'job_status.dart';

/// Color mappings for [JobStatus], centralizing the switch statements that
/// were duplicated across job detail/list screens and the kanban board.
///
/// Two palettes exist by design:
/// - [detail]: status badges on detail screens and job/contractor list cards.
/// - [pipeline]: kanban column accents where the emphasis differs.
class JobStatusColors {
  JobStatusColors._();

  /// Palette for status badges on detail screens and list cards.
  static Color detail(JobStatus status) {
    return switch (status) {
      JobStatus.quote => Colors.grey,
      JobStatus.scheduled => Colors.blue,
      JobStatus.inProgress => Colors.orange,
      JobStatus.complete => Colors.green,
      JobStatus.invoiced => Colors.purple,
      JobStatus.cancelled => Colors.red,
    };
  }

  /// Palette for the kanban pipeline board columns.
  static Color pipeline(JobStatus status) {
    return switch (status) {
      JobStatus.quote => Colors.blue,
      JobStatus.scheduled => Colors.orange,
      JobStatus.inProgress => Colors.amber[700]!,
      JobStatus.complete => Colors.green,
      JobStatus.invoiced => Colors.purple,
      JobStatus.cancelled => Colors.grey,
    };
  }
}
