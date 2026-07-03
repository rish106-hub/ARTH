class TaxDocument {
  final String id;
  final String fy;
  final String documentType;
  final String originalFilename;
  final String mimeType;
  final int byteSize;
  final String parseStatus;
  final Map<String, dynamic> parseSummary;
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
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );

  bool get needsConfirmation => parseStatus == 'needs_confirmation';
  bool get parsed => parseStatus == 'parsed';
  bool get unsupported => parseStatus == 'unsupported';

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
      default:
        return 'Stored';
    }
  }
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} MB';
}
