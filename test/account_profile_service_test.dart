import 'package:arth/models/account_profile.dart';
import 'package:arth/models/user_account.dart';
import 'package:arth/services/account_profile_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final user = UserAccount(
    uid: 'user-1',
    name: 'Rishav',
    email: 'rishav@example.com',
    createdAt: DateTime(2026, 7, 28),
  );
  final cached = AccountProfile(
    user: user,
    pan: const PanVaultStatus(
      present: true,
      maskedPan: '•••••1234F',
    ),
  );

  test('explicit missing PAN from server clears the cached PAN', () {
    final merged = mergeAccountProfileUpdate(
      AccountProfile(user: user, pan: PanVaultStatus.missing),
      cached,
      panIncluded: true,
    );

    expect(merged.pan.present, isFalse);
  });

  test('omitted PAN field keeps the last cached status', () {
    final merged = mergeAccountProfileUpdate(
      AccountProfile(user: user, pan: PanVaultStatus.missing),
      cached,
      panIncluded: false,
    );

    expect(merged.pan.present, isTrue);
    expect(merged.pan.maskedPan, '•••••1234F');
  });
}
