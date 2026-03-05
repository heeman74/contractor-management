import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../shared/models/user_role.dart';

/// Profile screen — shows the current user's info and active roles.
///
/// Phase 1: displays the mock user's ID, company, and role set.
/// Future phases will show real profile data: name, photo, contact info,
/// notification settings, and company details.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: switch (authState) {
        AuthAuthenticated(:final userId, :final companyId, :final roles) =>
          _ProfileContent(
            userId: userId,
            companyId: companyId,
            roles: roles,
            onLogout: () => ref.read(authNotifierProvider.notifier).logout(),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.userId,
    required this.companyId,
    required this.roles,
    required this.onLogout,
  });

  final String userId;
  final String companyId;
  final Set<UserRole> roles;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Avatar placeholder
        Center(
          child: CircleAvatar(
            radius: 48,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: const Icon(Icons.person, size: 48, color: Colors.white),
          ),
        ),
        const SizedBox(height: 24),
        // Info card
        Card(
          child: Column(
            children: [
              _InfoRow(label: 'User ID', value: userId),
              const Divider(height: 1),
              _InfoRow(label: 'Company ID', value: companyId),
              const Divider(height: 1),
              _InfoRow(
                label: 'Roles',
                value: roles.map((r) => r.name).join(', '),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Role badges
        Wrap(
          spacing: 8,
          children: roles
              .map(
                (role) => Chip(
                  label: Text(role.name.toUpperCase()),
                  avatar: Icon(_roleIcon(role), size: 16),
                  backgroundColor: _roleColor(role).withOpacity(0.15),
                  side: BorderSide(color: _roleColor(role).withOpacity(0.4)),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 32),
        // Phase 1 note
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.withOpacity(0.4)),
          ),
          child: const Text(
            'Phase 1 — Mock user. Real profiles with name, photo, and '
            'notification settings will be available in Phase 6.',
            style: TextStyle(fontSize: 12, color: Colors.amber),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.tonal(
          onPressed: onLogout,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.withOpacity(0.1),
            foregroundColor: Colors.red,
          ),
          child: const Text('Sign Out'),
        ),
      ],
    );
  }

  IconData _roleIcon(UserRole role) => switch (role) {
        UserRole.admin => Icons.admin_panel_settings_outlined,
        UserRole.contractor => Icons.construction_outlined,
        UserRole.client => Icons.person_outline,
      };

  Color _roleColor(UserRole role) => switch (role) {
        UserRole.admin => Colors.blue,
        UserRole.contractor => Colors.orange,
        UserRole.client => Colors.green,
      };
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
