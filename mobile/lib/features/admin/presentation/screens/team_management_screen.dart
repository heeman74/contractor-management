import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart' hide UserRole;
import '../../../../core/di/service_locator.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../../../features/users/presentation/providers/user_providers.dart';
import '../../../../shared/models/user_role.dart';

/// Admin team management screen — view members, add new ones, assign roles.
///
/// Follows the [ClientCrmScreen] pattern: ConsumerWidget with reactive
/// Drift streams, search filtering, FAB for primary action, and empty state.
class TeamManagementScreen extends ConsumerWidget {
  const TeamManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final companyId =
        authState is AuthAuthenticated ? authState.companyId : '';

    final usersAsync = ref.watch(companyUsersProvider(companyId));
    final searchQuery = ref.watch(teamSearchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Management'),
        backgroundColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SearchBar(
              hintText: 'Search by name or email…',
              leading: const Icon(Icons.search),
              trailing: [
                if (searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => ref
                        .read(teamSearchQueryProvider.notifier)
                        .state = '',
                  ),
              ],
              onChanged: (value) =>
                  ref.read(teamSearchQueryProvider.notifier).state = value,
            ),
          ),

          // Member list
          Expanded(
            child: usersAsync.when(
              data: (users) {
                final filtered = _filterUsers(users, searchQuery);
                if (filtered.isEmpty) {
                  return _EmptyState(hasSearch: searchQuery.isNotEmpty);
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    return _MemberCard(
                      user: filtered[index],
                      companyId: companyId,
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 16),
                    Text('Failed to load team members: $error'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddMemberSheet(context, companyId),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Member'),
      ),
    );
  }

  List<UserEntity> _filterUsers(List<UserEntity> users, String query) {
    if (query.isEmpty) return users;
    final lower = query.toLowerCase();
    return users.where((u) {
      final name =
          '${u.firstName ?? ''} ${u.lastName ?? ''}'.toLowerCase();
      return name.contains(lower) || u.email.toLowerCase().contains(lower);
    }).toList();
  }

  void _showAddMemberSheet(BuildContext context, String companyId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddMemberSheet(companyId: companyId),
    );
  }
}

// ---------------------------------------------------------------------------
// Member card
// ---------------------------------------------------------------------------

/// Card displaying a single team member with role chips and actions.
class _MemberCard extends ConsumerWidget {
  final UserEntity user;
  final String companyId;

  const _MemberCard({required this.user, required this.companyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(userRolesProvider(user.id));
    final roles = rolesAsync.value ?? [];

    final displayName = _buildDisplayName();
    final initials = _buildInitials();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            initials,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user.email,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (user.phone != null && user.phone!.isNotEmpty)
              Text(
                user.phone!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (roles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  children: roles
                      .map((r) => _RoleChip(role: r.role))
                      .toList(),
                ),
              ),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'assign_role') {
              _showAssignRoleDialog(context, user, companyId);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'assign_role',
              child: ListTile(
                leading: Icon(Icons.badge_outlined),
                title: Text('Assign Role'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildDisplayName() {
    final first = user.firstName ?? '';
    final last = user.lastName ?? '';
    final full = '$first $last'.trim();
    return full.isNotEmpty ? full : user.email;
  }

  String _buildInitials() {
    final first = user.firstName;
    final last = user.lastName;
    if (first != null && first.isNotEmpty && last != null && last.isNotEmpty) {
      return '${first[0]}${last[0]}'.toUpperCase();
    }
    if (first != null && first.isNotEmpty) return first[0].toUpperCase();
    return user.email[0].toUpperCase();
  }

  void _showAssignRoleDialog(
    BuildContext context,
    UserEntity user,
    String companyId,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _AssignRoleDialog(user: user, companyId: companyId),
    );
  }
}

// ---------------------------------------------------------------------------
// Role chip
// ---------------------------------------------------------------------------

class _RoleChip extends StatelessWidget {
  final UserRole role;

  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (role) {
      UserRole.admin => (Colors.blue.shade100, Colors.blue.shade800),
      UserRole.contractor => (Colors.orange.shade100, Colors.orange.shade800),
      UserRole.client => (Colors.green.shade100, Colors.green.shade800),
    };

    return Chip(
      label: Text(
        role.name[0].toUpperCase() + role.name.substring(1),
        style: TextStyle(fontSize: 12, color: fg),
      ),
      backgroundColor: bg,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

// ---------------------------------------------------------------------------
// Assign Role dialog
// ---------------------------------------------------------------------------

class _AssignRoleDialog extends StatefulWidget {
  final UserEntity user;
  final String companyId;

  const _AssignRoleDialog({required this.user, required this.companyId});

  @override
  State<_AssignRoleDialog> createState() => _AssignRoleDialogState();
}

class _AssignRoleDialogState extends State<_AssignRoleDialog> {
  UserRole _selectedRole = UserRole.contractor;
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assign Role'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<UserRole>(
            initialValue: _selectedRole,
            decoration: const InputDecoration(
              labelText: 'Role',
              border: OutlineInputBorder(),
            ),
            items: UserRole.values
                .map(
                  (r) => DropdownMenuItem(
                    value: r,
                    child: Text(
                      r.name[0].toUpperCase() + r.name.substring(1),
                    ),
                  ),
                )
                .toList(),
            onChanged: _submitting
                ? null
                : (value) {
                    if (value != null) setState(() => _selectedRole = value);
                  },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Assign'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final db = getIt<AppDatabase>();
      final now = DateTime.now();
      await db.userDao.assignRole(
        UserRolesCompanion.insert(
          id: Value(const Uuid().v4()),
          userId: widget.user.id,
          companyId: widget.companyId,
          role: _selectedRole.name,
          createdAt: now,
        ),
      );

      // Auto-create ClientProfile when assigning client role
      if (_selectedRole == UserRole.client) {
        await db.jobDao.insertClientProfile(
          ClientProfilesCompanion.insert(
            id: Value(const Uuid().v4()),
            companyId: widget.companyId,
            userId: widget.user.id,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Failed to assign role. Please try again.';
        });
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Add Member bottom sheet
// ---------------------------------------------------------------------------

class _AddMemberSheet extends StatefulWidget {
  final String companyId;

  const _AddMemberSheet({required this.companyId});

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  UserRole _selectedRole = UserRole.contractor;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add Team Member',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email *',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Email is required';
                  }
                  if (!value.contains('@')) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _firstNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'First Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lastNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Last Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole>(
                initialValue: _selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                items: UserRole.values
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(
                          r.name[0].toUpperCase() + r.name.substring(1),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedRole = value);
                        }
                      },
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child:
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Add Member'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final db = getIt<AppDatabase>();
      final userId = const Uuid().v4();
      final now = DateTime.now();

      // Insert user
      await db.userDao.insertUser(
        UsersCompanion.insert(
          id: Value(userId),
          companyId: widget.companyId,
          email: _emailCtrl.text.trim(),
          firstName: Value(_firstNameCtrl.text.trim().isNotEmpty
              ? _firstNameCtrl.text.trim()
              : null),
          lastName: Value(_lastNameCtrl.text.trim().isNotEmpty
              ? _lastNameCtrl.text.trim()
              : null),
          phone: Value(_phoneCtrl.text.trim().isNotEmpty
              ? _phoneCtrl.text.trim()
              : null),
          version: const Value(1),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Assign role
      await db.userDao.assignRole(
        UserRolesCompanion.insert(
          id: Value(const Uuid().v4()),
          userId: userId,
          companyId: widget.companyId,
          role: _selectedRole.name,
          createdAt: now,
        ),
      );

      // Auto-create ClientProfile when role is client
      if (_selectedRole == UserRole.client) {
        await db.jobDao.insertClientProfile(
          ClientProfilesCompanion.insert(
            id: Value(const Uuid().v4()),
            companyId: widget.companyId,
            userId: userId,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Failed to add member. Please try again.';
        });
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final bool hasSearch;

  const _EmptyState({required this.hasSearch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasSearch ? Icons.search_off : Icons.groups_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              hasSearch
                  ? 'No members match your search'
                  : 'No team members yet',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              hasSearch
                  ? 'Try a different search term or clear the search.'
                  : 'Tap the "Add Member" button to invite contractors, '
                      'clients, and admins to your team.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
