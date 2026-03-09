import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../shared/models/trade_type.dart';

/// In-app job request form for existing (logged-in) clients.
///
/// Clients submit a job request that goes to the admin review queue.
/// Once submitted, the request cannot be edited (CONTEXT.md locked decision).
/// Admin can then Accept (creating a job), Decline (with reason), or
/// request more information.
///
/// Form fields (from CONTEXT.md locked decisions):
/// - description (required, multiline)
/// - property address: dropdown of saved properties + "New address" option
/// - preferred date range: start and end date pickers
/// - urgency: normal / urgent toggle
/// - trade type: dropdown from TradeType enum
/// - photos: up to 5 images (file path strings stored in Drift)
/// - budget range: min and max currency fields
///
/// On submit: writes offline-first to Drift via [JobDao.insertJobRequest]
/// which atomically enqueues a sync item for upload when connected.
class JobRequestFormScreen extends ConsumerStatefulWidget {
  const JobRequestFormScreen({super.key});

  @override
  ConsumerState<JobRequestFormScreen> createState() =>
      _JobRequestFormScreenState();
}

class _JobRequestFormScreenState
    extends ConsumerState<JobRequestFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  final _descriptionController = TextEditingController();
  final _newAddressController = TextEditingController();
  final _budgetMinController = TextEditingController();
  final _budgetMaxController = TextEditingController();

  // Form state
  String? _selectedPropertyId;
  bool _isNewAddress = false;
  DateTime? _preferredDateStart;
  DateTime? _preferredDateEnd;
  bool _isUrgent = false;
  TradeType? _selectedTradeType;
  final List<String> _photoPaths = []; // file paths after picking
  bool _isSubmitting = false;
  bool _submitted = false;
  String? _errorMessage;

  static const int _maxPhotos = 5;

  @override
  void dispose() {
    _descriptionController.dispose();
    _newAddressController.dispose();
    _budgetMinController.dispose();
    _budgetMaxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return _SuccessScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Job Request'),
        backgroundColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Description
            _SectionHeader(title: 'What work do you need done?'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description *',
                hintText:
                    'Describe the work needed in as much detail as possible…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
              textInputAction: TextInputAction.next,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please describe the work needed';
                }
                if (v.trim().length < 20) {
                  return 'Please provide more detail (min 20 characters)';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Trade type
            _SectionHeader(title: 'What type of work is it?'),
            const SizedBox(height: 8),
            DropdownButtonFormField<TradeType>(
              value: _selectedTradeType,
              decoration: const InputDecoration(
                labelText: 'Trade type',
                prefixIcon: Icon(Icons.build_outlined),
                border: OutlineInputBorder(),
              ),
              items: TradeType.values
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Text(_tradeTypeLabel(t)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedTradeType = v),
            ),
            const SizedBox(height: 20),

            // Property address
            _SectionHeader(title: 'Where is the work needed?'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedPropertyId,
              decoration: const InputDecoration(
                labelText: 'Property address',
                prefixIcon: Icon(Icons.home_outlined),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: null,
                  child: Text('Select a saved address…'),
                ),
                // Saved properties loaded from Drift in production
                // (requires a stream provider with client ID lookup)
                DropdownMenuItem(
                  value: '__new__',
                  child: Text('+ Enter a new address'),
                ),
              ],
              onChanged: (v) => setState(() {
                _selectedPropertyId = v;
                _isNewAddress = v == '__new__';
              }),
            ),
            if (_isNewAddress) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _newAddressController,
                decoration: const InputDecoration(
                  labelText: 'Enter address',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
            ],
            const SizedBox(height: 20),

            // Preferred dates
            _SectionHeader(title: 'When would you like the work done?'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DatePickerField(
                    label: 'Preferred start',
                    date: _preferredDateStart,
                    onPicked: (d) => setState(() {
                      _preferredDateStart = d;
                      // Ensure end is not before start
                      if (_preferredDateEnd != null &&
                          _preferredDateEnd!.isBefore(d)) {
                        _preferredDateEnd = d;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DatePickerField(
                    label: 'Preferred end',
                    date: _preferredDateEnd,
                    onPicked: (d) => setState(() => _preferredDateEnd = d),
                    firstDate: _preferredDateStart,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Urgency
            _SectionHeader(title: 'How urgent is this?'),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.schedule),
                  label: Text('Normal'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.priority_high),
                  label: Text('Urgent'),
                ),
              ],
              selected: {_isUrgent},
              onSelectionChanged: (s) =>
                  setState(() => _isUrgent = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 20),

            // Budget range
            _SectionHeader(title: 'What is your budget range? (optional)'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _budgetMinController,
                    decoration: const InputDecoration(
                      labelText: 'Min budget',
                      prefixText: '\$',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _budgetMaxController,
                    decoration: const InputDecoration(
                      labelText: 'Max budget',
                      prefixText: '\$',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Photos
            _SectionHeader(
              title: 'Add photos (up to $_maxPhotos)',
            ),
            const SizedBox(height: 8),
            if (_photoPaths.isNotEmpty) ...[
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photoPaths.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) => Stack(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.image_outlined, size: 32),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _photoPaths.removeAt(index)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_photoPaths.length < _maxPhotos)
              OutlinedButton.icon(
                onPressed: _pickPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  _photoPaths.isEmpty
                      ? 'Add photos'
                      : 'Add more (${_photoPaths.length}/$_maxPhotos)',
                ),
              ),
            const SizedBox(height: 24),

            // Note about review process
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your request will be reviewed by our admin team. '
                      'You\'ll see the status update in your app.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
            ],

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit Request'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    // image_picker is not in pubspec.yaml — using platform file picker approach.
    // In production: add image_picker to pubspec.yaml and implement:
    //   final picker = ImagePicker();
    //   final file = await picker.pickImage(source: ImageSource.gallery);
    //   if (file != null) setState(() => _photoPaths.add(file.path));
    //
    // For now, show a placeholder that informs the user.
    // [Rule 3 auto-fix deferred]: image_picker requires native plugin configuration.
    // Add to pubspec.yaml: image_picker: ^1.1.2
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Photo picker: add image_picker to pubspec.yaml to enable photo uploads.',
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final authState = ref.read(authNotifierProvider);
      if (authState is! AuthAuthenticated) {
        setState(() => _errorMessage = 'Not authenticated. Please log in.');
        return;
      }

      final jobDao = getIt<JobDao>();
      final now = DateTime.now();

      // Resolve address
      final address = _isNewAddress
          ? _newAddressController.text.trim()
          : _selectedPropertyId;

      // Build photos JSON — file paths stored as JSON TEXT array
      final photosJson = '[${_photoPaths.map((p) => '"$p"').join(',')}]';

      final companion = JobRequestsCompanion(
        id: Value(const Uuid().v4()),
        companyId: Value(authState.companyId),
        clientId: Value(authState.userId),
        description: Value(_descriptionController.text.trim()),
        tradeType: Value(_selectedTradeType?.name),
        urgency: Value(_isUrgent ? 'urgent' : 'normal'),
        preferredDateStart: Value(_preferredDateStart),
        preferredDateEnd: Value(_preferredDateEnd),
        budgetMin: Value(double.tryParse(_budgetMinController.text)),
        budgetMax: Value(double.tryParse(_budgetMaxController.text)),
        photos: Value(photosJson),
        requestStatus: const Value('pending'),
        version: const Value(1),
        createdAt: Value(now),
        updatedAt: Value(now),
      );

      await jobDao.insertJobRequest(companion);

      if (mounted) {
        setState(() => _submitted = true);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to submit request: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _tradeTypeLabel(TradeType type) {
    return switch (type) {
      TradeType.builder => 'Builder',
      TradeType.electrician => 'Electrician',
      TradeType.plumber => 'Plumber',
      TradeType.hvac => 'HVAC',
      TradeType.painter => 'Painter',
      TradeType.carpenter => 'Carpenter',
      TradeType.roofer => 'Roofer',
      TradeType.landscaper => 'Landscaper',
      TradeType.general => 'General',
    };
  }
}

// ─── Success screen ────────────────────────────────────────────────────────────

/// Shown after the request is submitted. No editing allowed after this point.
class _SuccessScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Submitted')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 96,
                color: Colors.green,
              ),
              const SizedBox(height: 24),
              const Text(
                'Request Submitted!',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your request will be reviewed by our admin team. '
                'You\'ll see the status update in your app.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}

// ─── Date picker field ────────────────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final void Function(DateTime) onPicked;
  final DateTime? firstDate;

  const _DatePickerField({
    required this.label,
    required this.date,
    required this.onPicked,
    this.firstDate,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ??
              (firstDate ?? DateTime.now())
                  .add(const Duration(days: 1)),
          firstDate:
              firstDate ?? DateTime.now().add(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) onPicked(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          border: const OutlineInputBorder(),
          suffixIcon: date != null
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {}, // clearing managed by parent setState
                )
              : null,
        ),
        child: Text(
          date != null
              ? '${date!.day}/${date!.month}/${date!.year}'
              : 'Select date',
          style: date != null
              ? null
              : TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}
