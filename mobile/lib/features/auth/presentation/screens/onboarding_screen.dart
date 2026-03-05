import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/models/user_role.dart';
import '../providers/auth_provider.dart';

/// Onboarding / role selection screen — Phase 1 testing stub.
///
/// In v2 (Phase 6), this will become the real company signup / login screen:
/// - Company admin enters email and password
/// - JWT is issued, tenant is resolved, real roles are loaded from backend
///
/// For Phase 1 testing: presents three role selection buttons so developers and
/// testers can navigate the app as different user types without a real backend.
/// Each button sets a mock authenticated user with the selected role.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.build_circle_outlined,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 24),
              const Text(
                'ContractorHub',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Phase 1 — Select a role to explore the app',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 48),
              _RoleButton(
                label: 'Sign in as Admin',
                subtitle: 'Manage team, clients, and jobs',
                icon: Icons.admin_panel_settings_outlined,
                color: Colors.blue,
                onTap: () => _signInAs(context, ref, UserRole.admin),
              ),
              const SizedBox(height: 16),
              _RoleButton(
                label: 'Sign in as Contractor',
                subtitle: 'View jobs, manage availability',
                icon: Icons.construction_outlined,
                color: Colors.orange,
                onTap: () => _signInAs(context, ref, UserRole.contractor),
              ),
              const SizedBox(height: 16),
              _RoleButton(
                label: 'Sign in as Client',
                subtitle: 'Track job status, view portal',
                icon: Icons.person_outline,
                color: Colors.green,
                onTap: () => _signInAs(context, ref, UserRole.client),
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () => _signInAsMultiRole(context, ref),
                child: const Text('Sign in as Admin + Contractor (multi-role test)'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _signInAs(BuildContext context, WidgetRef ref, UserRole role) {
    ref.read(authNotifierProvider.notifier).setMockUser(
          userId: 'mock-user-${role.name}',
          companyId: 'mock-company-001',
          roles: {role},
        );
    // go_router will redirect automatically once auth state changes
  }

  void _signInAsMultiRole(BuildContext context, WidgetRef ref) {
    ref.read(authNotifierProvider.notifier).setMockUser(
          userId: 'mock-user-multirole',
          companyId: 'mock-company-001',
          roles: {UserRole.admin, UserRole.contractor},
        );
  }
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
