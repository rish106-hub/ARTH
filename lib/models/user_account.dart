import 'dart:convert';

class UserAccount {
  final String name;
  final String email;
  final bool biometricsEnabled;
  final DateTime createdAt;
  final String? uid; // Firebase anonymous UID

  const UserAccount({
    required this.name,
    required this.email,
    required this.createdAt,
    this.biometricsEnabled = false,
    this.uid,
  });

  /// Initials for avatar display (up to 2 chars)
  String get initials {
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
    bool? biometricsEnabled,
    DateTime? createdAt,
    String? uid,
  }) {
    return UserAccount(
      name: name ?? this.name,
      email: email ?? this.email,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      createdAt: createdAt ?? this.createdAt,
      uid: uid ?? this.uid,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'biometricsEnabled': biometricsEnabled,
        'createdAt': createdAt.toIso8601String(),
        'uid': uid,
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
        name: json['name'] as String? ?? '',
        // backward compat: old accounts stored phone instead of email
        email: json['email'] as String? ?? json['phone'] as String? ?? '',
        biometricsEnabled: json['biometricsEnabled'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        uid: json['uid'] as String?,
      );

  String toJsonString() => jsonEncode(toJson());

  factory UserAccount.fromJsonString(String raw) =>
      UserAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
