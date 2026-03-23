import 'package:flutter/material.dart';

import '../../domain/ai_models.dart';

/// Preview card for AI-generated trade scopes in the intake flow.
///
/// Shows a reorderable list of trade scope rows with drag handles,
/// color swatches, editable names, and delete buttons.
/// The "Create Project" CTA is enabled when at least one scope exists.
class TradeScopePreviewCard extends StatefulWidget {
  const TradeScopePreviewCard({
    required this.scopes,
    required this.onScopeReordered,
    required this.onScopeDeleted,
    required this.onScopeRenamed,
    required this.onCreateProject,
    this.isLoading = false,
    super.key,
  });

  final List<AiTradeScope> scopes;

  /// Called with (oldIndex, newIndex) when a scope is reordered via drag.
  final Function(int oldIndex, int newIndex) onScopeReordered;

  /// Called with the scope index to remove.
  final Function(int index) onScopeDeleted;

  /// Called with (index, newName) when a scope name is edited.
  final Function(int index, String newName) onScopeRenamed;

  /// Called to create the project with the current scopes.
  final VoidCallback onCreateProject;

  /// True during loading — shows shimmer skeleton rows.
  final bool isLoading;

  @override
  State<TradeScopePreviewCard> createState() => _TradeScopePreviewCardState();
}

class _TradeScopePreviewCardState extends State<TradeScopePreviewCard> {
  // Track which scope is being edited inline
  int? _editingIndex;
  final Map<int, TextEditingController> _editControllers = {};

  @override
  void dispose() {
    for (final c in _editControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trade Breakdown',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            if (widget.isLoading)
              _buildLoadingSkeleton(colorScheme)
            else if (widget.scopes.isEmpty)
              _buildEmptyState(textTheme, colorScheme)
            else
              _buildScopeList(colorScheme),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.scopes.isNotEmpty && !widget.isLoading
                    ? widget.onCreateProject
                    : null,
                child: const Text('Create Project'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton(ColorScheme colorScheme) {
    return Column(
      children: List.generate(3, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildEmptyState(TextTheme textTheme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Waiting for AI to suggest trade scopes...',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildScopeList(ColorScheme colorScheme) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.scopes.length,
      onReorder: widget.onScopeReordered,
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        final scope = widget.scopes[index];
        return _ScopeRow(
          key: ValueKey(scope.id.isEmpty ? index : scope.id),
          scope: scope,
          index: index,
          isEditing: _editingIndex == index,
          editController: _editControllers.putIfAbsent(
            index,
            () => TextEditingController(text: scope.tradeName),
          ),
          onEditStart: () => setState(() => _editingIndex = index),
          onEditEnd: (newName) {
            widget.onScopeRenamed(index, newName);
            setState(() => _editingIndex = null);
          },
          onDelete: () => widget.onScopeDeleted(index),
        );
      },
    );
  }
}

class _ScopeRow extends StatelessWidget {
  const _ScopeRow({
    required this.scope,
    required this.index,
    required this.isEditing,
    required this.editController,
    required this.onEditStart,
    required this.onEditEnd,
    required this.onDelete,
    super.key,
  });

  final AiTradeScope scope;
  final int index;
  final bool isEditing;
  final TextEditingController editController;
  final VoidCallback onEditStart;
  final Function(String newName) onEditEnd;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Drag handle
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Icon(
                Icons.drag_handle,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // Color swatch
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _parseColor(scope.tradeColor),
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.outline, width: 0.5),
            ),
          ),
          const SizedBox(width: 8),

          // Trade name (editable on tap)
          Expanded(
            child: isEditing
                ? TextField(
                    controller: editController,
                    autofocus: true,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      border: UnderlineInputBorder(),
                    ),
                    onSubmitted: onEditEnd,
                    onEditingComplete: () => onEditEnd(editController.text),
                  )
                : GestureDetector(
                    onTap: onEditStart,
                    child: Text(
                      scope.tradeName,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
          ),

          // Delete button
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Remove ${scope.tradeName}',
              style: IconButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      }
    } catch (_) {}
    return const Color(0xFF3949AB); // fallback indigo
  }
}
