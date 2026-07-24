class TaxDocument {
  final String id;
  final String fy;
  final String documentType;
  final String originalFilename;
  final String mimeType;
  final int byteSize;
  final String parseStatus;
  final Map<String, dynamic> parseSummary;
  final String? userLabel;
  final String? notes;
  final List<String> tags;
  final String vaultStatus;
  final String reviewStatus;
  final Map<String, dynamic> confirmedFields;
  final DateTime? reviewedAt;
  final DateTime? archivedAt;
  final DateTime? createdAt;

  const TaxDocument({
    required this.id,
    required this.fy,
    required this.documentType,
    required this.originalFilename,
    required this.mimeType,
    required this.byteSize,
    required this.parseStatus,
    required this.parseSummary,
    this.userLabel,
    this.notes,
    this.tags = const [],
    this.vaultStatus = 'active',
    this.reviewStatus = 'not_reviewed',
    this.confirmedFields = const {},
    this.reviewedAt,
    this.archivedAt,
    this.createdAt,
  });

  factory TaxDocument.fromJson(Map<String, dynamic> json) => TaxDocument(
        id: json['id'] as String? ?? '',
        fy: json['fy'] as String? ?? '',
        documentType: json['documentType'] as String? ?? 'otherTaxDocument',
        originalFilename: json['originalFilename'] as String? ?? 'document',
        mimeType: json['mimeType'] as String? ?? '',
        byteSize: json['byteSize'] as int? ?? 0,
        parseStatus: json['parseStatus'] as String? ?? 'metadata_ready',
        parseSummary: json['parseSummary'] as Map<String, dynamic>? ?? const {},
        userLabel: json['userLabel'] as String?,
        notes: json['notes'] as String?,
        tags: (json['tags'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(),
        vaultStatus: json['vaultStatus'] as String? ?? 'active',
        reviewStatus: json['reviewStatus'] as String? ?? 'not_reviewed',
        confirmedFields:
            json['confirmedFields'] as Map<String, dynamic>? ?? const {},
        reviewedAt: DateTime.tryParse(json['reviewedAt'] as String? ?? ''),
        archivedAt: DateTime.tryParse(json['archivedAt'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );

  bool get needsConfirmation => parseStatus == 'needs_confirmation';
  bool get parsed => parseStatus == 'parsed';
  bool get unsupported => parseStatus == 'unsupported';
  bool get archived => vaultStatus == 'archived';
  bool get active => !archived;
  bool get reviewed => reviewStatus == 'reviewed' || parsed;
  bool get needsReview =>
      needsConfirmation || reviewStatus == 'needs_review' || unsupported;

  bool get isPayslip {
    final parser = parseSummary['parser']?.toString() ?? '';
    if (documentType == 'payslip' ||
        parseSummary['detectedDocumentType'] == 'payslip' ||
        parser.contains('payslip')) {
      return true;
    }
    final fields =
        confirmedFields.isNotEmpty ? confirmedFields : extractedFields;
    return fields['earnings'] is List &&
        fields['deductions'] is List &&
        (fields.containsKey('netSalary') ||
            fields.containsKey('grossEarnings'));
  }

  String get displayName => userLabel?.trim().isNotEmpty == true
      ? userLabel!.trim()
      : originalFilename;

  Map<String, dynamic> get extractedFields =>
      parseSummary['extractedFields'] as Map<String, dynamic>? ?? const {};

  String get parseStatusLabel {
    switch (parseStatus) {
      case 'needs_confirmation':
        return 'Review needed';
      case 'parsed':
        return 'Confirmed';
      case 'unsupported':
        return 'Manual review';
      case 'failed':
        return 'Failed';
      default:
        return 'Stored';
    }
  }
}

class DocumentVaultSummary {
  final int total;
  final int active;
  final int archived;
  final int needsReview;
  final int ready;
  final int unsupported;

  const DocumentVaultSummary({
    required this.total,
    required this.active,
    required this.archived,
    required this.needsReview,
    required this.ready,
    required this.unsupported,
  });

  factory DocumentVaultSummary.fromDocuments(List<TaxDocument> documents) {
    final active = documents.where((doc) => doc.active).toList();
    return DocumentVaultSummary(
      total: documents.length,
      active: active.length,
      archived: documents.length - active.length,
      needsReview: active.where((doc) => doc.needsReview).length,
      ready: active.where((doc) => doc.reviewed).length,
      unsupported: active.where((doc) => doc.unsupported).length,
    );
  }
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} MB';
}
