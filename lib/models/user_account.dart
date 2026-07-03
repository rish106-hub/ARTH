import 'dart:convert';

class UserAccount {
  final String name;
  final String email;
  final String? phoneNumber;
  final String? avatarInitials;
  final String? avatarColor;
  final bool biometricsEnabled;
  final DateTime createdAt;
  final String? uid; // Server-side user id

  const UserAccount({
    required this.name,
    required this.email,
    required this.createdAt,
    this.phoneNumber,
    this.avatarInitials,
    this.avatarColor,
    this.biometricsEnabled = false,
    this.uid,
  });

  /// Initials for avatar display (up to 2 chars)
  String get initials {
    if (avatarInitials != null && avatarInitials!.trim().isNotEmpty) {
      return avatarInitials!.trim().toUpperCase();
    }
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'A';
  }

  bool get isSynced => uid != null;

  UserAccount copyWith({
    String? name,
    String? email,
    String? phoneNumber,
    String? avatarInitials,
    String? avatarColor,
    bool? biometricsEnabled,
    DateTime? createdAt,
    String? uid,
  }) {
    return UserAccount(
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      avatarInitials: avatarInitials ?? this.avatarInitials,
      avatarColor: avatarColor ?? this.avatarColor,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      createdAt: createdAt ?? this.createdAt,
      uid: uid ?? this.uid,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'phoneNumber': phoneNumber,
        'avatarInitials': avatarInitials,
        'avatarColor': avatarColor,
        'biometricsEnabled': biometricsEnabled,
        'createdAt': createdAt.toIso8601String(),
        'uid': uid,
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
        name: json['name'] as String? ?? '',
        // backward compat: old accounts stored phone instead of email
        email: json['email'] as String? ?? json['phone'] as String? ?? '',
        phoneNumber: json['phoneNumber'] as String?,
        avatarInitials: json['avatarInitials'] as String?,
        avatarColor: json['avatarColor'] as String?,
        biometricsEnabled: json['biometricsEnabled'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        uid: json['uid'] as String?,
      );

  String toJsonString() => jsonEncode(toJson());

  factory UserAccount.fromJsonString(String raw) =>
      UserAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
