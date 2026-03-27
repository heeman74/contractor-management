import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/logging/app_logger.dart';
import '../providers/foreman_provider.dart';

/// Form screen for foremen to submit daily project status updates.
///
/// Includes:
/// - Project selector (dropdown of assigned projects)
/// - Status text (multiline)
/// - Weather conditions (optional)
/// - Workers on site (optional number)
/// - Safety incidents (number, default 0)
/// - Blockers (optional multiline)
/// - Photo attachment (placeholder for future implementation)
/// - Submit button
class DailyStatusScreen extends ConsumerStatefulWidget {
  const DailyStatusScreen({super.key});

  @override
  ConsumerState<DailyStatusScreen> createState() => _DailyStatusScreenState();
}

class _DailyStatusScreenState extends ConsumerState<DailyStatusScreen> {
  final _formKey = GlobalKey<FormState>();
  final _statusTextController = TextEditingController();
  final _weatherController = TextEditingController();
  final _workersController = TextEditingController();
  final _safetyIncidentsController = TextEditingController(text: '0');
  final _blockersController = TextEditingController();

  String? _selectedProjectId;
  bool _isSubmitting = false;

  static const _tag = 'DailyStatusScreen';

  @override
  void dispose() {
    _statusTextController.dispose();
    _weatherController.dispose();
    _workersController.dispose();
    _safetyIncidentsController.dispose();
    _blockersController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a project')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(foremanRepositoryProvider);

      final data = <String, dynamic>{
        'project_id': _selectedProjectId,
        'status_text': _statusTextController.text.trim(),
        'report_date': DateTime.now().toIso8601String().split('T').first,
        'safety_incidents':
            int.tryParse(_safetyIncidentsController.text.trim()) ?? 0,
      };

      final weather = _weatherController.text.trim();
      if (weather.isNotEmpty) {
        data['weather_conditions'] = weather;
      }

      final workers = int.tryParse(_workersController.text.trim());
      if (workers != null) {
        data['workers_on_site'] = workers;
      }

      final blockers = _blockersController.text.trim();
      if (blockers.isNotEmpty) {
        data['blockers'] = blockers;
      }

      await repo.createStatusUpdate(data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status update submitted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        // Invalidate the status updates cache for this project
        ref.invalidate(statusUpdatesProvider(_selectedProjectId!));
        ref.invalidate(latestStatusProvider(_selectedProjectId!));
        context.pop();
      }
    } catch (e, st) {
      AppLogger.error(_tag, 'Failed to submit status update',
          error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to submit status update'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final assignedProjects = ref.watch(assignedProjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Status Update'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Project selector
            assignedProjects.when(
              data: (projects) {
                if (projects.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No projects assigned to you.'),
                    ),
                  );
                }
                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Project *',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: _selectedProjectId,
                  items: projects.map((p) {
                    final id = p['project_id'] is String
                        ? p['project_id'] as String
                        : p['id'] is String
                            ? p['id'] as String
                            : '';
                    final name = p['project_name'] is String
                        ? p['project_name'] as String
                        : p['name'] is String
                            ? p['name'] as String
                            : 'Unknown Project';
                    return DropdownMenuItem(
                      value: id,
                      child: Text(name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedProjectId = value);
                  },
                  validator: (value) =>
                      value == null ? 'Please select a project' : null,
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Failed to load projects. Pull down to retry.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Status text
            TextFormField(
              controller: _statusTextController,
              decoration: const InputDecoration(
                labelText: 'Status Update *',
                hintText: 'Describe today\'s progress...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 5,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Status update is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Weather conditions
            TextFormField(
              controller: _weatherController,
              decoration: const InputDecoration(
                labelText: 'Weather Conditions',
                hintText: 'e.g., Sunny, 75F, light wind',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wb_sunny_outlined),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),

            // Workers on site and Safety incidents in a row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _workersController,
                    decoration: const InputDecoration(
                      labelText: 'Workers on Site',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.people_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _safetyIncidentsController,
                    decoration: const InputDecoration(
                      labelText: 'Safety Incidents',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.health_and_safety_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Blockers
            TextFormField(
              controller: _blockersController,
              decoration: const InputDecoration(
                labelText: 'Blockers',
                hintText: 'Any issues preventing progress...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.block_outlined),
              ),
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),

            // Photo attachment placeholder
            OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Photo attachment coming soon'),
                  ),
                );
              },
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add Photos'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 24),

            // Submit button
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Submit Status Update'),
            ),
          ],
        ),
      ),
    );
  }
}
