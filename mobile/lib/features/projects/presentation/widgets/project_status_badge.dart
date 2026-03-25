import 'package:flutter/material.dart';

/// A small chip-style badge that maps status strings to colors.
///
/// Supports project statuses (draft, planning, active, on_hold, complete,
/// archived, cancelled), trade scope statuses (not_started, in_progress,
/// blocked), and task statuses (not_started, in_progress, complete, blocked).
///
/// Usage:
///   ProjectStatusBadge(status: project.status)
///   ProjectStatusBadge(status: scope.status)
///   ProjectStatusBadge(status: task.status)
class ProjectStatusBadge extends StatelessWidget {
  const ProjectStatusBadge({required this.status, this.dense = false, super.key});

  final String status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (label, bgColor, textColor) = _colorForStatus(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: dense ? 9 : 11,
          fontWeight: FontWeight.w600,
          color: textColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static (String label, Color bg, Color fg) _colorForStatus(String status) {
    return switch (status) {
      // Project statuses
      'draft' => ('Draft', const Color(0xFFE0E0E0), const Color(0xFF757575)),
      'planning' => ('Planning', const Color(0xFFBBDEFB), const Color(0xFF1565C0)),
      'active' => ('Active', const Color(0xFFC8E6C9), const Color(0xFF2E7D32)),
      'on_hold' => ('On Hold', const Color(0xFFFFF9C4), const Color(0xFFF57F17)),
      'complete' => ('Complete', const Color(0xFFB2DFDB), const Color(0xFF00695C)),
      'archived' => ('Archived', const Color(0xFFEEEEEE), const Color(0xFF9E9E9E)),
      'cancelled' => ('Cancelled', const Color(0xFFFFCDD2), const Color(0xFFC62828)),
      // Trade scope statuses
      'not_started' => ('Not Started', const Color(0xFFE0E0E0), const Color(0xFF757575)),
      'in_progress' => ('In Progress', const Color(0xFFBBDEFB), const Color(0xFF1565C0)),
      'blocked' => ('Blocked', const Color(0xFFFFCDD2), const Color(0xFFC62828)),
      // Fallback
      _ => (status, const Color(0xFFEEEEEE), const Color(0xFF616161)),
    };
  }
}
