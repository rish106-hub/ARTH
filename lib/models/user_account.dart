import 'dart:convert';

enum AuthMethod { manual, google }

class UserAccount {
  final String name;
  final String phone; // primary identifier — stored masked: ••••••7890
  final String incomeRange;
  final bool biometricsEnabled;
  final DateTime createdAt;

  // PAN is optional — user may add it later in tax profile
  final String? panCard; // stored masked: AXXXX9999A

  // Cloud identity (populated after Firebase Auth)
  final String? uid; // Firebase UID — null until first sync
  final String? email; // Google email — null for manual accounts
  final AuthMethod authMethod;

  const UserAccount({
    required this.name,
    required this.phone,
    required this.incomeRange,
    required this.biometricsEnabled,
    required this.createdAt,
    this.panCard,
    this.uid,
    this.email,
    this.authMethod = AuthMethod.manual,
  });

  /// Mask phone for storage/display: show only last 4 digits
  static String maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return '••••••${digits}';
    return '••••••${digits.substring(digits.length - 4)}';
  }

  /// Mask PAN for storage: only first char + last 5 are visible
  static String maskPan(String rawPan) {
    if (rawPan.length < 10) return rawPan;
    return '${rawPan[0]}XXXX${rawPan.substring(5)}';
  }

  /// Initials for avatar display (up to 2 chars)
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'A';
  }

  /// Display label shown under name in the account card
  String get displayIdentifier {
    if (phone.isNotEmpty) return maskPhone(phone);
    if (panCard != null && panCard!.isNotEmpty) return panCard!;
    return '';
  }

  bool get isGoogleUser => authMethod == AuthMethod.google;
  bool get isSynced => uid != null;

  UserAccount copyWith({
    String? name,
    String? phone,
    String? incomeRange,
    bool? biometricsEnabled,
    DateTime? createdAt,
    String? panCard,
    String? uid,
    String? email,
    AuthMethod? authMethod,
  }) {
    return UserAccount(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      incomeRange: incomeRange ?? this.incomeRange,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      createdAt: createdAt ?? this.createdAt,
      panCard: panCard ?? this.panCard,
      uid: uid ?? this.uid,
      email: email ?? this.email,
      authMethod: authMethod ?? this.authMethod,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'incomeRange': incomeRange,
        'biometricsEnabled': biometricsEnabled,
        'createdAt': createdAt.toIso8601String(),
        'panCard': panCard,
        'uid': uid,
        'email': email,
        'authMethod': authMethod.name,
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
        name: json['name'] as String,
        // Backward compat: old accounts had panCard but no phone
        phone: (json['phone'] as String?) ?? '',
        incomeRange: (json['incomeRange'] as String?) ?? '',
        biometricsEnabled: (json['biometricsEnabled'] as bool?) ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        // Backward compat: old accounts stored panCard as required String
        panCard: json['panCard'] as String?,
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
