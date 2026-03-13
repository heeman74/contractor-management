import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../../../features/users/presentation/providers/user_providers.dart';
import '../providers/job_providers.dart';
import '../widgets/address_autocomplete_field.dart';

/// 4-step job creation wizard.
///
/// Step 1 — Client + Description
/// Step 2 — Address + Trade Type
/// Step 3 — Contractor + Scheduling (skipped offline — locked decision)
/// Step 4 — Review + Priority + Submit
///
/// All steps are tappable (experienced admin fast-path). Writes offline-first
/// to Drift via [JobDao.insertJob] which atomically enqueues a sync item.
///
/// Offline detection (locked project decision):
///   If [ConnectivityService.isConnected] is false, Step 3 is skipped and
///   the job is created at Quote stage with a visible info banner.
class JobWizardScreen extends ConsumerStatefulWidget {
  const JobWizardScreen({super.key});

  @override
  ConsumerState<JobWizardScreen> createState() => _JobWizardScreenState();
}

class _JobWizardScreenState extends ConsumerState<JobWizardScreen> {
  int _currentStep = 0;

  // Step 1 — Client + Description
  final _descriptionController = TextEditingController();
  String? _selectedClientId;

  // Step 2 — Address + Trade Type
  final _addressController = TextEditingController();
  String _selectedTradeType = 'General';

  // Step 3 — Contractor + Scheduling (optional at Quote)
  String? _selectedContractorId;
  int? _estimatedDurationMinutes;
  DateTime? _preferredDate;

  // Step 4 — Review + Priority + Notes
  String _priority = 'medium';
  final _notesController = TextEditingController();

  final _scrollController = ScrollController();

  bool _isSubmitting = false;
  String? _errorMessage;
  bool _isOffline = false;

  static const _tradeTypes = [
    'General',
    'Electrical',
    'Plumbing',
    'HVAC',
    'Carpentry',
    'Painting',
    'Roofing',
    'Landscaping',
    'Cleaning',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    // InternetConnection is a stateless utility — instantiate directly for
    // one-shot check. ConnectivityService is designed for background streaming
    // and is not registered in GetIt for direct injection.
    final connected = await InternetConnection().hasInternetAccess;
    if (mounted) {
      setState(() => _isOffline = !connected);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _isStep1Valid => _descriptionController.text.trim().length >= 10;

  bool get _isStep2Valid =>
      _selectedTradeType.isNotEmpty && _addressController.text.trim().isNotEmpty;

  // Step 3 is all optional — valid means user filled something.
  bool get _isStep3Valid =>
      _selectedContractorId != null || _preferredDate != null;

  StepState _stepState(int stepIndex, bool isValid) {
    if (_currentStep == stepIndex) return StepState.editing;
    if (_currentStep > stepIndex) {
      return isValid ? StepState.complete : StepState.error;
    }
    return StepState.indexed;
  }

  List<Step> _buildSteps() {
    final steps = <Step>[
      // ── Step 1: Client + Description ──────────────────────────────────────
      Step(
        title: const Text('Client & Job'),
        isActive: _currentStep >= 0,
        state: _stepState(0, _isStep1Valid),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Client selector — populated from users with 'client' role
            _buildClientSelector(),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Job description *',
                hintText: 'Describe the work required (min 10 characters)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              textInputAction: TextInputAction.next,
            ),
          ],
        ),
      ),

      // ── Step 2: Address + Trade Type ──────────────────────────────────────
      Step(
        title: const Text('Location & Trade'),
        isActive: _currentStep >= 1,
        state: _stepState(1, _isStep2Valid),
        content: Column(
          children: [
            AddressAutocompleteField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Service address',
                hintText: 'Start typing an address...',
                prefixIcon: Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedTradeType,
              decoration: const InputDecoration(
                labelText: 'Trade type *',
                prefixIcon: Icon(Icons.build_outlined),
                border: OutlineInputBorder(),
              ),
              items: _tradeTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedTradeType = v);
              },
            ),
          ],
        ),
      ),

      // ── Step 3: Contractor + Scheduling ──────────────────────────────────
      Step(
        title: const Text('Contractor & Schedule'),
        isActive: _currentStep >= 2,
        state: _stepState(2, _isStep3Valid),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isOffline)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  border: Border.all(color: Colors.amber),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You are offline. Contractor assignment will be '
                        'available when connectivity is restored.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            const Text(
              'Assign a contractor and set scheduling details. '
              'Leave blank to create at Quote stage.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
              const SizedBox(height: 16),
              // Contractor selector — populated from users with 'contractor' role
              _buildContractorSelector(),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(
                  _preferredDate == null
                      ? 'Preferred date (optional)'
                      : '${_preferredDate!.day}/${_preferredDate!.month}/${_preferredDate!.year}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate:
                        DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _preferredDate = picked);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Estimated duration (minutes)',
                  prefixIcon: Icon(Icons.timer_outlined),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  _estimatedDurationMinutes = int.tryParse(v);
                },
              ),
            ],
          ),
        ),

      // ── Step 4: Review + Priority + Submit ──────────────────────────────
      Step(
        title: const Text('Review & Submit'),
        isActive: _currentStep >= 3,
        state: _stepState(3, _isStep1Valid && _isStep2Valid),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Offline info banner
            if (_isOffline)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  border: Border.all(color: Colors.amber),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You are offline. The job will be created at Quote '
                        'stage. Assign a contractor when connectivity is restored.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // Summary card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ReviewRow(
                      label: 'Description',
                      value: _descriptionController.text.isEmpty
                          ? '(not set)'
                          : _descriptionController.text,
                    ),
                    _ReviewRow(
                      label: 'Trade',
                      value: _selectedTradeType,
                    ),
                    _ReviewRow(
                      label: 'Address',
                      value: _addressController.text.isEmpty
                          ? '(not set)'
                          : _addressController.text,
                    ),
                    if (!_isOffline) ...[
                      _ReviewRow(
                        label: 'Contractor',
                        value:
                            _selectedContractorId ?? 'Not assigned',
                      ),
                      _ReviewRow(
                        label: 'Preferred date',
                        value: _preferredDate == null
                            ? 'Not set'
                            : '${_preferredDate!.day}/${_preferredDate!.month}/${_preferredDate!.year}',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Priority selector
            const Text(
              'Priority',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'low', label: Text('Low')),
                ButtonSegment(value: 'medium', label: Text('Medium')),
                ButtonSegment(value: 'high', label: Text('High')),
              ],
              selected: {_priority},
              onSelectionChanged: (s) =>
                  setState(() => _priority = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 16),

            // Optional notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                prefixIcon: Icon(Icons.notes_outlined),
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),

          ],
        ),
      ),
    ];

    return steps;
  }

  String _displayName(UserEntity u) {
    final first = u.firstName ?? '';
    final last = u.lastName ?? '';
    final full = '$first $last'.trim();
    return full.isNotEmpty ? full : u.email;
  }

  Widget _buildClientSelector() {
    final authState = ref.watch(authNotifierProvider);
    final companyId =
        authState is AuthAuthenticated ? authState.companyId : '';
    final clientsAsync = ref.watch(companyClientsProvider(companyId));
    final clients = clientsAsync.value ?? [];

    return DropdownButtonFormField<String>(
      initialValue: _selectedClientId,
      decoration: const InputDecoration(
        labelText: 'Client (optional)',
        prefixIcon: Icon(Icons.person_outline),
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String>(
          child: Text('No client selected'),
        ),
        ...clients.map(
          (c) => DropdownMenuItem<String>(
            value: c.id,
            child: Text(_displayName(c)),
          ),
        ),
      ],
      onChanged: (v) => setState(() => _selectedClientId = v),
    );
  }

  Widget _buildContractorSelector() {
    final authState = ref.watch(authNotifierProvider);
    final companyId =
        authState is AuthAuthenticated ? authState.companyId : '';
    final contractorsAsync =
        ref.watch(companyContractorsProvider(companyId));
    final contractors = contractorsAsync.value ?? [];

    return DropdownButtonFormField<String>(
      initialValue: _selectedContractorId,
      decoration: const InputDecoration(
        labelText: 'Assign contractor (optional)',
        prefixIcon: Icon(Icons.engineering_outlined),
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String>(
          child: Text('No contractor assigned yet'),
        ),
        ...contractors.map(
          (c) => DropdownMenuItem<String>(
            value: c.id,
            child: Text(_displayName(c)),
          ),
        ),
      ],
      onChanged: (v) => setState(() => _selectedContractorId = v),
    );
  }

  bool _validateCurrentStep() {
    if (_currentStep == 0) {
      if (_descriptionController.text.trim().length < 10) {
        setState(() => _errorMessage =
            'Description must be at least 10 characters.');
        return false;
      }
    }
    if (_currentStep == 1) {
      if (_selectedTradeType.isEmpty) {
        setState(() => _errorMessage = 'Please select a trade type.');
        return false;
      }
    }
    setState(() => _errorMessage = null);
    return true;
  }

  Future<void> _submit() async {
    if (_descriptionController.text.trim().length < 10) {
      setState(() =>
          _errorMessage = 'Description must be at least 10 characters.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final authState = ref.read(authNotifierProvider);
      if (authState is! AuthAuthenticated) {
        setState(() => _errorMessage = 'Not authenticated.');
        return;
      }

      final dao = ref.read(jobDaoProvider);
      final now = DateTime.now();
      final jobId = const Uuid().v4();

      final statusHistoryJson = jsonEncode([
        {
          'status': 'quote',
          'timestamp': now.toIso8601String(),
          'user_id': authState.userId,
        }
      ]);

      final companion = JobsCompanion(
        id: Value(jobId),
        companyId: Value(authState.companyId),
        description: Value(_descriptionController.text.trim()),
        tradeType: Value(_selectedTradeType),
        status: const Value('quote'),
        statusHistory: Value(statusHistoryJson),
        priority: Value(_priority),
        tags: const Value('[]'),
        version: const Value(1),
        createdAt: Value(now),
        updatedAt: Value(now),
        clientId: Value(_selectedClientId),
        contractorId: Value(_selectedContractorId),
        notes: Value(
          _notesController.text.isEmpty ? null : _notesController.text,
        ),
        estimatedDurationMinutes: Value(_estimatedDurationMinutes),
        scheduledCompletionDate: Value(_preferredDate),
      );

      await dao.insertJob(companion);

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job created successfully')),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to create job: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps();
    final isLastStep = _currentStep == steps.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Job'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stepper(
        key: ValueKey(_isOffline),
        controller: _scrollController,
        currentStep: _currentStep,
        type: StepperType.vertical,
        // All steps tappable — experienced admin fast-path
        onStepTapped: (step) => setState(() {
          _currentStep = step;
          _errorMessage = null;
        }),
        onStepContinue: () {
          if (!_validateCurrentStep()) return;
          if (isLastStep) {
            _submit();
          } else {
            setState(() {
              _currentStep++;
              _errorMessage = null;
            });
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() {
              _currentStep--;
              _errorMessage = null;
            });
          } else {
            context.pop();
          }
        },
        controlsBuilder: (context, details) {
          return Padding(
            padding: EdgeInsets.only(
              top: 16,
              bottom: isLastStep ? 80 : 0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    FilledButton(
                      onPressed:
                          _isSubmitting ? null : details.onStepContinue,
                      child: _isSubmitting && isLastStep
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(isLastStep ? 'Create Job' : 'Continue'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: details.onStepCancel,
                      child: Text(_currentStep == 0 ? 'Cancel' : 'Back'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
        steps: steps,
      ),
    );
  }
}

// ─── Review row helper ────────────────────────────────────────────────────────

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
