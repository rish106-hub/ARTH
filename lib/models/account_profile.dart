import 'dart:convert';

import 'user_account.dart';

class PanVaultStatus {
  final bool present;
  final String? maskedPan;
  final String? consentVersion;
  final DateTime? updatedAt;

  const PanVaultStatus({
    required this.present,
    this.maskedPan,
    this.consentVersion,
    this.updatedAt,
  });

  static const missing = PanVaultStatus(present: false);

  Map<String, dynamic> toJson() => {
        'present': present,
        'maskedPan': maskedPan,
        'consentVersion': consentVersion,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory PanVaultStatus.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String?;
    final present = json['present'] as bool? ?? status == 'present';
    final updatedRaw = json['updatedAt'] as String?;
    return PanVaultStatus(
      present: present,
      maskedPan: json['maskedPan'] as String?,
      consentVersion: json['consentVersion'] as String?,
      updatedAt: updatedRaw == null ? null : DateTime.tryParse(updatedRaw),
    );
  }
}

class AccountProfile {
  final UserAccount user;
  final PanVaultStatus pan;

  const AccountProfile({
    required this.user,
    required this.pan,
  });

  AccountProfile copyWith({
    UserAccount? user,
    PanVaultStatus? pan,
  }) {
    return AccountProfile(
      user: user ?? this.user,
      pan: pan ?? this.pan,
    );
  }

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'pan': pan.toJson(),
      };

  String toJsonString() => jsonEncode(toJson());

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return AccountProfile(
      user: UserAccount(
        uid: user['id'] as String? ?? user['uid'] as String?,
        name: user['name'] as String? ?? '',
        email: user['email'] as String? ?? '',
        phoneNumber: user['phoneNumber'] as String?,
        avatarInitials: user['avatarInitials'] as String?,
        avatarColor: user['avatarColor'] as String?,
        createdAt: DateTime.parse(
          user['createdAt'] as String? ?? DateTime.now().toIso8601String(),
        ),
      ),
      pan: PanVaultStatus.fromJson(
        json['pan'] as Map<String, dynamic>? ?? const {'status': 'missing'},
      ),
    );
  }

  factory AccountProfile.fromJsonString(String raw) =>
      AccountProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
