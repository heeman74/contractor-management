import 'package:flutter/material.dart';

/// Default inspection checklist items used when a trade scope has no
/// custom [inspectionChecklist] JSON defined.
const kDefaultInspectionChecklist = [
  {"item": "Quality of work is acceptable", "id": "q1"},
  {"item": "Correct materials were used", "id": "q2"},
  {"item": "Work area is clean and safe", "id": "q3"},
  {"item": "Safety requirements are met", "id": "q4"},
];

/// A stateful widget that renders a list of checkable inspection items.
///
/// Used by the GC on [TaskDetailScreen] to evaluate a completed task
/// before approving or rejecting it.
///
/// Callbacks:
/// - [onAllCheckedChanged]: fires with `true` when every item is checked,
///   `false` when any item is unchecked. Used to enable/disable the Approve
///   button in the inspection bottom bar.
/// - [onResultsChanged]: fires on every toggle, emitting a list of
///   `{"item": String, "checked": bool}` maps suitable for JSON encoding
///   into [TaskInspection.checklistResults].
class InspectionChecklist extends StatefulWidget {
  const InspectionChecklist({
    required this.items,
    required this.onAllCheckedChanged,
    required this.onResultsChanged,
    super.key,
  });

  /// List of checklist items. Each map must have an "item" key (String).
  final List<Map<String, dynamic>> items;

  /// Called whenever the "all checked" state changes.
  final ValueChanged<bool> onAllCheckedChanged;

  /// Called whenever any item's checked state changes, with the current
  /// results list (`[{"item": ..., "checked": ...}, ...]`).
  final ValueChanged<List<Map<String, dynamic>>> onResultsChanged;

  @override
  State<InspectionChecklist> createState() => _InspectionChecklistState();
}

class _InspectionChecklistState extends State<InspectionChecklist> {
  late final Map<int, bool> _checked;

  @override
  void initState() {
    super.initState();
    _checked = {for (var i = 0; i < widget.items.length; i++) i: false};
  }

  void _onToggle(int index, bool? value) {
    setState(() {
      _checked[index] = value ?? false;
    });
    final allChecked =
        _checked.values.every((v) => v) && widget.items.isNotEmpty;
    widget.onAllCheckedChanged(allChecked);
    final results = List.generate(
      widget.items.length,
      (i) => {
        "item": widget.items[i]["item"] as String,
        "checked": _checked[i] ?? false,
      },
    );
    widget.onResultsChanged(results);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (widget.items.isEmpty) {
      return Text(
        'No checklist items.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Column(
      children: List.generate(widget.items.length, (i) {
        return CheckboxListTile(
          value: _checked[i] ?? false,
          onChanged: (val) => _onToggle(i, val),
          title: Text(
            widget.items[i]["item"] as String? ?? '',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeColor: colorScheme.primary,
          controlAffinity: ListTileControlAffinity.leading,
        );
      }),
    );
  }
}
