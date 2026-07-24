import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao, QuoteDao, InvoiceDao;
import '../../../../shared/utils/date_format_utils.dart';
import '../../domain/task_status.dart';
import '../providers/project_providers.dart';
import 'inspection_checklist.dart';

/// Task lifecycle status shown as a colored chip.
class TaskStatusBadge extends StatelessWidget {
  const TaskStatusBadge({required this.status, super.key});
  final String status;

  static const _colors = <String, Color>{
    TaskStatus.complete: Color(0xFF388E3C),
    TaskStatus.inProgress: Color(0xFF1565C0),
    TaskStatus.blocked: Color(0xFFD32F2F),
    TaskStatus.rejected: Color(0xFFB71C1C),
  };
  static const _fallbackColor = Color(0xFF9E9E9E);

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        status.replaceAll('_', ' '),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Colors.white),
      ),
      backgroundColor: _colors[status] ?? _fallbackColor,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

/// Task priority shown as a colored chip.
class TaskPriorityBadge extends StatelessWidget {
  const TaskPriorityBadge({required this.priority, super.key});
  final String priority;

  static const _colors = <String, Color>{
    TaskPriority.urgent: Color(0xFFD32F2F),
    TaskPriority.high: Color(0xFFF57C00),
    TaskPriority.medium: Color(0xFF1565C0),
    TaskPriority.low: Color(0xFF9E9E9E),
  };
  static const _fallbackColor = Color(0xFF9E9E9E);

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        priority,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Colors.white),
      ),
      backgroundColor: _colors[priority] ?? _fallbackColor,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

/// Renders a materials list parsed from the task's JSON-encoded field.
class TaskMaterialsList extends StatelessWidget {
  const TaskMaterialsList({required this.materialsJson, super.key});
  final String materialsJson;

  List<String> _parseMaterials() {
    final trimmed = materialsJson.trim();
    if (!trimmed.startsWith('[')) return const [];
    try {
      final parsed = jsonDecode(trimmed) as List<dynamic>;
      return parsed
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final materials = _parseMaterials();
    if (materials.isEmpty) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Materials needed:',
          style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        ...materials.map(
          (material) => Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• '),
                Expanded(
                  child: Text(material, style: textTheme.bodySmall),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// GC-only total time summary derived from the task's estimated hours.
class TaskTotalTimeSummary extends ConsumerWidget {
  const TaskTotalTimeSummary({required this.taskId, super.key});
  final String taskId;

  static const int _minutesPerHour = 60;

  String _timeLabel(ProjectTask? task) {
    final estimatedHours = task?.estimatedHours;
    if (estimatedHours == null || estimatedHours <= 0) return 'No time logged';
    final totalMinutes = (estimatedHours * _minutesPerHour).round();
    final hours = totalMinutes ~/ _minutesPerHour;
    final minutes = totalMinutes % _minutesPerHour;
    return hours > 0 ? '$hours hrs $minutes min' : '$minutes min';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(taskByIdProvider(taskId)).value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Total Time Logged'),
            subtitle: Text(_timeLabel(task)),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
    );
  }
}

/// GC-only status transition timeline: Created → In Progress → Complete.
class TaskStatusTimeline extends StatelessWidget {
  const TaskStatusTimeline({required this.task, super.key});
  final ProjectTask task;

  static const _notReached = 'N/A';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final startLabel = task.startDate != null
        ? DateFormatUtils.formatDateTime(task.startDate!)
        : _notReached;
    final completeLabel = task.status == TaskStatus.complete
        ? DateFormatUtils.formatDateTime(task.updatedAt)
        : _notReached;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text(
            'Status Timeline',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _TimelineRow(
            color: Colors.grey,
            label: 'Created',
            timestamp: DateFormatUtils.formatDateTime(task.createdAt),
          ),
          const _TimelineDivider(),
          _TimelineRow(
            color: const Color(0xFF1565C0),
            label: 'In Progress',
            timestamp: startLabel,
          ),
          const _TimelineDivider(),
          _TimelineRow(
            color: const Color(0xFF388E3C),
            label: 'Complete',
            timestamp: completeLabel,
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.color,
    required this.label,
    required this.timestamp,
  });
  final Color color;
  final String label;
  final String timestamp;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: textTheme.bodySmall)),
        Text(
          timestamp,
          style: textTheme.bodySmall?.copyWith(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _TimelineDivider extends StatelessWidget {
  const _TimelineDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: Container(width: 2, height: 16, color: Colors.grey.shade300),
    );
  }
}

/// GC-only inspection checklist section wrapping [InspectionChecklist].
class TaskInspectionChecklistSection extends StatelessWidget {
  const TaskInspectionChecklistSection({
    required this.scope,
    required this.onAllCheckedChanged,
    required this.onResultsChanged,
    super.key,
  });

  final TradeScope? scope;
  final ValueChanged<bool> onAllCheckedChanged;
  final ValueChanged<List<Map<String, dynamic>>> onResultsChanged;

  List<Map<String, dynamic>> _defaultChecklist() {
    return kDefaultInspectionChecklist
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<Map<String, dynamic>> _parseChecklist() {
    final checklistJson = scope?.inspectionChecklist;
    if (checklistJson == null || checklistJson.isEmpty) {
      return _defaultChecklist();
    }
    try {
      final parsed = jsonDecode(checklistJson) as List<dynamic>;
      return parsed
          .whereType<Map<String, dynamic>>()
          .map((entry) {
            final item = (entry['item'] ?? entry['label'] ?? '').toString();
            return <String, dynamic>{'item': item, 'id': entry['id'] ?? ''};
          })
          .where((entry) => (entry['item'] as String).isNotEmpty)
          .toList();
    } catch (_) {
      return _defaultChecklist();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text(
            'Inspection Checklist',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          InspectionChecklist(
            items: _parseChecklist(),
            onAllCheckedChanged: onAllCheckedChanged,
            onResultsChanged: onResultsChanged,
          ),
        ],
      ),
    );
  }
}

/// A document attachment tile that opens the file in the system viewer.
class TaskDocListTile extends StatelessWidget {
  const TaskDocListTile({required this.attachment, super.key});
  final TaskAttachment attachment;

  static const int _filenameMaxLength = 40;
  static const int _bytesPerKb = 1024;
  static const int _bytesPerMb = 1024 * 1024;

  String get _filename =>
      attachment.caption ??
      attachment.localPath?.split('/').last ??
      'attachment.pdf';

  String _displayName() {
    return _filename.length > _filenameMaxLength
        ? '${_filename.substring(0, _filenameMaxLength)}...'
        : _filename;
  }

  @override
  Widget build(BuildContext context) {
    final localPath = attachment.localPath;
    return ListTile(
      leading: const Icon(Icons.picture_as_pdf, color: Color(0xFFD32F2F)),
      title: Text(
        _displayName(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: localPath != null
          ? Text(_fileSize(localPath),
              style: Theme.of(context).textTheme.bodySmall)
          : null,
      onTap: () => _openFile(context),
      contentPadding: EdgeInsets.zero,
    );
  }

  Future<void> _openFile(BuildContext context) async {
    final path = attachment.localPath;
    if (path == null) return;
    try {
      final uri = Uri.file(path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app available to open this file.')),
        );
      }
    } catch (error) {
      debugPrint('[TaskDocListTile] File open error: $error');
    }
  }

  String _fileSize(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return 'File not found';
      final bytes = file.lengthSync();
      if (bytes < _bytesPerKb) return '${bytes}B';
      if (bytes < _bytesPerMb) {
        return '${(bytes / _bytesPerKb).toStringAsFixed(1)}KB';
      }
      return '${(bytes / _bytesPerMb).toStringAsFixed(1)}MB';
    } catch (_) {
      return '';
    }
  }
}
