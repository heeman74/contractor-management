import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_names.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../../../features/users/presentation/providers/user_providers.dart';
import '../../../../shared/models/user_role.dart';

/// Fixed header showing contractor avatar and name at the top of a lane.
///
/// Does not scroll — remains visible while the time body scrolls vertically.
/// Height is determined by content (no fixed constraint) so it adapts to
/// font scaling and admin/non-admin states without overflow.
///
/// Admin long-press: wrap the header in a [GestureDetector] that opens
/// schedule settings for the contractor. Per CONTEXT.md locked decision:
/// "Contractor schedule management: both inline quick actions from calendar
/// (long-press for day off, adjust hours) AND a separate settings screen".
class ContractorLaneHeader extends ConsumerWidget {
  const ContractorLaneHeader({
    required this.contractor,
    required this.laneWidth,
    super.key,
  });

  final UserEntity contractor;
  final double laneWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = _contractorName(contractor);
    final initials = _initials(displayName);
    final theme = Theme.of(context);
    final authState = ref.watch(authNotifierProvider);
    final isAdmin = authState is AuthAuthenticated &&
        authState.roles.contains(UserRole.admin);
    final rolesAsync = ref.watch(userRolesProvider(contractor.id));
    final roles = rolesAsync.value ?? [];

    final headerContent = Container(
      width: laneWidth,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          // Role labels — show all roles for this contractor
          if (roles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 2,
                children: roles.map((r) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: _roleColor(r.role).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      r.role.name,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        color: _roleColor(r.role),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          // Admin-only hint: shows tooltip on long-press
          if (isAdmin)
            const Icon(Icons.more_horiz, size: 10, color: Colors.grey),
        ],
      ),
    );

    // Admin users: long-press opens schedule settings for this contractor.
    // Contractors: no long-press action (they use the gear icon in their own screen).
    if (isAdmin) {
      return GestureDetector(
        onLongPress: () {
          context.push(
            RouteNames.scheduleSettings,
            extra: contractor.id,
          );
        },
        child: Tooltip(
          message: 'Long press to manage schedule',
          child: headerContent,
        ),
      );
    }

    return headerContent;
  }

  Color _roleColor(UserRole role) {
    return switch (role) {
      UserRole.owner => Colors.deepPurple,
      UserRole.admin => Colors.purple,
      UserRole.projectManager => Colors.indigo,
      UserRole.gc => Colors.teal,
      UserRole.foreman => Colors.brown,
      UserRole.contractor => Colors.blue,
      UserRole.worker => Colors.cyan,
      UserRole.client => Colors.teal,
    };
  }

  String _contractorName(UserEntity user) {
    final firstName = user.firstName ?? '';
    final lastName = user.lastName ?? '';
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '$firstName $lastName';
    }
    if (firstName.isNotEmpty) return firstName;
    return user.email.split('@').first;
  }

  String _initials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
