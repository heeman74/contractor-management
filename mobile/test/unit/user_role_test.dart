import 'package:contractorhub/shared/models/user_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserRole.fromString', () {
    test('maps every backend slug to the correct value', () {
      expect(UserRole.fromString('owner'), UserRole.owner);
      expect(UserRole.fromString('admin'), UserRole.admin);
      expect(UserRole.fromString('project_manager'), UserRole.projectManager);
      expect(UserRole.fromString('gc'), UserRole.gc);
      expect(UserRole.fromString('foreman'), UserRole.foreman);
      expect(UserRole.fromString('contractor'), UserRole.contractor);
      expect(UserRole.fromString('worker'), UserRole.worker);
      expect(UserRole.fromString('client'), UserRole.client);
    });

    test('returns null for an unknown slug instead of throwing', () {
      expect(UserRole.fromString('superadmin'), isNull);
      expect(UserRole.fromString(''), isNull);
    });

    test('is filtered cleanly by whereType (login parse path)', () {
      final roles = ['admin', 'superadmin', 'project_manager']
          .map(UserRole.fromString)
          .whereType<UserRole>()
          .toSet();
      expect(roles, {UserRole.admin, UserRole.projectManager});
    });
  });

  group('slug', () {
    test('round-trips with fromString', () {
      for (final role in UserRole.values) {
        expect(UserRole.fromString(role.slug), role);
      }
    });

    test('uses snake_case for project manager', () {
      expect(UserRole.projectManager.slug, 'project_manager');
    });
  });

  group('displayLabel', () {
    test('returns human labels', () {
      expect(UserRole.owner.displayLabel, 'Owner');
      expect(UserRole.projectManager.displayLabel, 'Project Manager');
      expect(UserRole.gc.displayLabel, 'General Contractor');
      expect(UserRole.worker.displayLabel, 'Worker');
    });
  });

  group('capability getters', () {
    test('isAdminLevel is owner/admin only', () {
      expect(UserRole.owner.isAdminLevel, isTrue);
      expect(UserRole.admin.isAdminLevel, isTrue);
      expect(UserRole.projectManager.isAdminLevel, isFalse);
      expect(UserRole.gc.isAdminLevel, isFalse);
    });

    test('isManagerLevel includes project manager but not gc', () {
      expect(UserRole.projectManager.isManagerLevel, isTrue);
      expect(UserRole.owner.isManagerLevel, isTrue);
      expect(UserRole.gc.isManagerLevel, isFalse);
      expect(UserRole.contractor.isManagerLevel, isFalse);
    });

    test('isGcLevel includes gc but not project manager', () {
      expect(UserRole.gc.isGcLevel, isTrue);
      expect(UserRole.admin.isGcLevel, isTrue);
      expect(UserRole.projectManager.isGcLevel, isFalse);
      expect(UserRole.worker.isGcLevel, isFalse);
    });

    test('field roles have no elevated capability', () {
      for (final role in [UserRole.contractor, UserRole.worker, UserRole.client]) {
        expect(role.isAdminLevel, isFalse);
        expect(role.isManagerLevel, isFalse);
        expect(role.isGcLevel, isFalse);
      }
    });
  });
}
