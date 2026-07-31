import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../models/paycheck.dart';
import '../../../models/tax_document.dart';
import '../models/recovery_models.dart';

class ClaimPackArtifact {
  const ClaimPackArtifact({
    required this.filename,
    required this.bytes,
    required this.summaryPdf,
  });

  final String filename;
  final Uint8List bytes;
  final Uint8List summaryPdf;
}

class ClaimPackService {
  const ClaimPackService();

  Future<ClaimPackArtifact> build({
    required ClaimCase claim,
    required PaycheckState paycheck,
    required List<TaxDocument> evidence,
    required Map<String, List<int>> evidenceBytes,
    required bool userApproved,
  }) async {
    if (!userApproved) {
      throw StateError('Approve the claim summary before export.');
    }
    if (evidence.isEmpty) {
      throw StateError('Select at least one evidence file.');
    }
    for (final document in evidence) {
      if (!evidenceBytes.containsKey(document.id)) {
        throw StateError('Evidence download is incomplete.');
      }
    }

    final pdf = pw.Document(
      title: '${claim.label} claim',
      author: 'ARTH',
      subject: 'User-approved reimbursement claim summary',
    );
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'CLAIM CASEFILE',
              style: const pw.TextStyle(
                fontSize: 10,
                letterSpacing: 1.8,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              claim.label,
              style: const pw.TextStyle(
                fontSize: 26,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              _money(claim.amount),
              style: const pw.TextStyle(
                fontSize: 22,
                color: PdfColors.green800,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 24),
            _row('Employee', paycheck.employeeName),
            _row(
              'Employer',
              paycheck.employer.trim().isEmpty
                  ? 'Not added'
                  : paycheck.employer,
            ),
            _row('Pay period', paycheck.payPeriod),
            _row('Reason', claim.detail),
            if (claim.dueDate != null) _row('Deadline', _date(claim.dueDate!)),
            pw.SizedBox(height: 24),
            pw.Text(
              'Evidence spine',
              style: const pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 12),
            ...evidence.asMap().entries.map(
                  (entry) => pw.Container(
                    padding: const pw.EdgeInsets.only(bottom: 12),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        left: pw.BorderSide(
                          width: 2,
                          color: PdfColors.green700,
                        ),
                      ),
                    ),
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 12),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            '${entry.key + 1}. ${entry.value.displayName}',
                            style: const pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            '${entry.value.documentType} | ${entry.value.parseStatusLabel}',
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            if (claim.note.trim().isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                'User note',
                style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(claim.note.trim()),
            ],
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey400),
            pw.Text(
              'Prepared after user review. ARTH has not submitted this claim or verified employer approval.',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ),
      ),
    );
    final summaryPdf = Uint8List.fromList(await pdf.save());
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes(
          'ARTH-claim-summary.pdf',
          summaryPdf,
        ),
      );
    for (final document in evidence) {
      archive.addFile(
        ArchiveFile.bytes(
          _safeFilename(document.displayName),
          evidenceBytes[document.id]!,
        ),
      );
    }
    final zip = ZipEncoder().encode(archive);
    return ClaimPackArtifact(
      filename: 'ARTH-${_safeStem(claim.label)}-claim-pack.zip',
      bytes: Uint8List.fromList(zip),
      summaryPdf: summaryPdf,
    );
  }

  static pw.Widget _row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 88,
              child: pw.Text(
                label,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ),
            pw.Expanded(child: pw.Text(value)),
          ],
        ),
      );

  static String _money(int value) {
    final raw = value.abs().toString();
    final tail = raw.length > 3 ? raw.substring(raw.length - 3) : raw;
    var head = raw.length > 3 ? raw.substring(0, raw.length - 3) : '';
    final groups = <String>[];
    while (head.length > 2) {
      groups.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) groups.insert(0, head);
    final formatted = groups.isEmpty ? tail : '${groups.join(',')},$tail';
    return '${value < 0 ? '-' : ''}INR $formatted';
  }

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  static String _safeFilename(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_').trim();
    return safe.isEmpty ? 'evidence' : safe;
  }

  static String _safeStem(String value) {
    final safe = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return safe.isEmpty ? 'reimbursement' : safe;
  }
}
