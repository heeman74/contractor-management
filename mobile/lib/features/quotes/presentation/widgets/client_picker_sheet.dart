import 'package:flutter/material.dart';

import '../../data/quote_client_repository.dart';
import '../../domain/quote_client.dart';

/// Choose the client a quote is for, or add one that is not on the roster yet.
///
/// Returns the chosen [QuoteClient], or null if dismissed.
///
/// Exists because the send transition refuses a quote with no client: without a
/// way to pick one, mobile could report that refusal but never resolve it.
class ClientPickerSheet extends StatefulWidget {
  const ClientPickerSheet({required this.repository, super.key});

  final QuoteClientRepository repository;

  static Future<QuoteClient?> show(
    BuildContext context, {
    required QuoteClientRepository repository,
  }) {
    return showModalBottomSheet<QuoteClient>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ClientPickerSheet(repository: repository),
      ),
    );
  }

  @override
  State<ClientPickerSheet> createState() => _ClientPickerSheetState();
}

class _ClientPickerSheetState extends State<ClientPickerSheet> {
  final _searchController = TextEditingController();
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  List<QuoteClient> _clients = const [];
  bool _isLoading = true;
  bool _isCreating = false;
  bool _showCreateForm = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The Add button enables once an email is typed, and enabling is decided at
    // build time — without this the field could be filled and the button would
    // stay dead.
    _emailController.addListener(_onEmailChanged);
    _load();
  }

  void _onEmailChanged() => setState(() {});

  @override
  void dispose() {
    _emailController.removeListener(_onEmailChanged);
    _searchController.dispose();
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _load({String? search}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final clients = await widget.repository.listClients(search: search);
      if (!mounted) return;
      setState(() {
        _clients = clients;
        _isLoading = false;
      });
    } on QuoteClientException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _create() async {
    setState(() {
      _isCreating = true;
      _error = null;
    });
    try {
      final created = await widget.repository.createClient(
        email: _emailController.text,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
      );
      if (!mounted) return;
      Navigator.pop(context, created);
    } on QuoteClientException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isCreating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _showCreateForm ? 'New client' : 'Choose a client',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(
                _error!,
                key: const Key('client_picker_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            if (_showCreateForm) ..._buildCreateForm() else ..._buildList(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCreateForm() {
    return [
      TextField(
        key: const Key('client_email_field'),
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      TextField(
        key: const Key('client_first_name_field'),
        controller: _firstNameController,
        decoration: const InputDecoration(labelText: 'First name'),
      ),
      TextField(
        key: const Key('client_last_name_field'),
        controller: _lastNameController,
        decoration: const InputDecoration(labelText: 'Last name'),
      ),
      const SizedBox(height: 8),
      const Text(
        'Adding a client does not give them a login.',
        style: TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          TextButton(
            onPressed: _isCreating
                ? null
                : () => setState(() => _showCreateForm = false),
            child: const Text('Back'),
          ),
          const Spacer(),
          FilledButton(
            key: const Key('client_create_button'),
            onPressed: _isCreating || _emailController.text.trim().isEmpty
                ? null
                : _create,
            child: Text(_isCreating ? 'Adding…' : 'Add client'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildList() {
    return [
      TextField(
        key: const Key('client_search_field'),
        controller: _searchController,
        decoration: const InputDecoration(
          labelText: 'Search clients',
          prefixIcon: Icon(Icons.search),
        ),
        onSubmitted: (value) => _load(search: value),
      ),
      const SizedBox(height: 12),
      if (_isLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_clients.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('No clients yet.'),
        )
      else
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _clients.length,
            itemBuilder: (context, index) {
              final client = _clients[index];
              return ListTile(
                key: Key('client_option_${client.userId}'),
                title: Text(client.displayName),
                subtitle: Text(client.email),
                onTap: () => Navigator.pop(context, client),
              );
            },
          ),
        ),
      const Divider(),
      TextButton.icon(
        key: const Key('client_add_new_button'),
        onPressed: () => setState(() {
          _showCreateForm = true;
          _error = null;
        }),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add a new client'),
      ),
    ];
  }
}
