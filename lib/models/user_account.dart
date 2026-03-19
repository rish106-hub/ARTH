import 'dart:convert';

enum AuthMethod { manual, google }

class UserAccount {
  final String name;
  final String panCard;       // stored masked: AXXXX9999A
  final String incomeRange;
  final bool biometricsEnabled;
  final DateTime createdAt;

  // Cloud identity (populated after Firebase Auth)
  final String? uid;          // Firebase UID — null until first sync
  final String? email;        // Google email — null for manual accounts
  final AuthMethod authMethod;

  const UserAccount({
    required this.name,
    required this.panCard,
    required this.incomeRange,
    required this.biometricsEnabled,
    required this.createdAt,
    this.uid,
    this.email,
    this.authMethod = AuthMethod.manual,
  });

  /// Mask PAN for storage: only first char + last 5 are visible
  static String maskPan(String rawPan) {
    if (rawPan.length < 10) return rawPan;
    return '${rawPan[0]}XXXX${rawPan.substring(5)}';
  }

  /// Initials for avatar display (up to 2 chars)
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'A';
  }

  bool get isGoogleUser => authMethod == AuthMethod.google;
  bool get isSynced => uid != null;

  UserAccount copyWith({
    String? name,
    String? panCard,
    String? incomeRange,
    bool? biometricsEnabled,
    DateTime? createdAt,
    String? uid,
    String? email,
    AuthMethod? authMethod,
  }) {
    return UserAccount(
      name: name ?? this.name,
      panCard: panCard ?? this.panCard,
      incomeRange: incomeRange ?? this.incomeRange,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      createdAt: createdAt ?? this.createdAt,
      uid: uid ?? this.uid,
      email: email ?? this.email,
      authMethod: authMethod ?? this.authMethod,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'panCard': panCard,
        'incomeRange': incomeRange,
        'biometricsEnabled': biometricsEnabled,
        'createdAt': createdAt.toIso8601String(),
        'uid': uid,
        'email': email,
        'authMethod': authMethod.name,
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
        name: json['name'] as String,
        panCard: json['panCard'] as String,
        incomeRange: (json['incomeRange'] as String?) ?? '',
        biometricsEnabled: (json['biometricsEnabled'] as bool?) ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        uid: json['uid'] as String?,
        email: json['email'] as String?,
        authMethod: AuthMethod.values.firstWhere(
          (e) => e.name == (json['authMethod'] as String?),
          orElse: () => AuthMethod.manual,
        ),
      );

  String toJsonString() => jsonEncode(toJson());

  factory UserAccount.fromJsonString(String raw) =>
      UserAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
