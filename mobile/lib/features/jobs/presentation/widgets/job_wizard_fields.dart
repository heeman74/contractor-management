import 'package:flutter/material.dart';

import '../../../users/domain/user_entity.dart';

/// Amber info banner shown when the wizard detects the device is offline.
class OfflineInfoBanner extends StatelessWidget {
  const OfflineInfoBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        border: Border.all(color: Colors.amber),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Dropdown selecting an optional [UserEntity] (client or contractor).
///
/// Renders a leading "none" option followed by the provided [users]. Replaces
/// the two near-identical selector methods in the wizard.
class UserSelectorDropdown extends StatelessWidget {
  const UserSelectorDropdown({
    required this.label,
    required this.icon,
    required this.emptyOptionLabel,
    required this.users,
    required this.selectedUserId,
    required this.onChanged,
    super.key,
  });

  final String label;
  final IconData icon;
  final String emptyOptionLabel;
  final List<UserEntity> users;
  final String? selectedUserId;
  final ValueChanged<String?> onChanged;

  static String displayName(UserEntity user) {
    final fullName = '${user.firstName ?? ''} ${user.lastName ?? ''}'.trim();
    return fullName.isNotEmpty ? fullName : user.email;
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selectedUserId,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem<String>(child: Text(emptyOptionLabel)),
        ...users.map(
          (user) => DropdownMenuItem<String>(
            value: user.id,
            child: Text(displayName(user)),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}
