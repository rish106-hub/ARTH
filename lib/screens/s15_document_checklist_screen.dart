import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/tax_document.dart';
import '../models/tax_readiness.dart';
import '../providers/paycheck_provider.dart';
import '../providers/tax_document_provider.dart';
import '../providers/tax_readiness_provider.dart';
import '../providers/tax_year_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/server_api_service.dart';
import '../services/on_device_document_ocr_service.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../widgets/animated_number.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';

class DocumentChecklistScreen extends ConsumerWidget {
  const DocumentChecklistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checklist = ref.watch(documentChecklistProvider);
    final documentsAsync = ref.watch(taxDocumentProvider);
    final documents = documentsAsync.asData?.value ?? const <TaxDocument>[];
    final summary = DocumentVaultSummary.fromDocuments(documents);
    final activeYear = ref.watch(activeTaxYearProvider);
    final percent = documentReadinessPercent(checklist);
    final neededItems = taxDocumentItems
        .where((item) => _documentsFor(item.id, documents).isEmpty)
        .toList();
    final remainingCount =
        neededItems.where((item) => !(checklist[item.id] ?? false)).length;
    final reviewDocuments =
        documents.where((doc) => doc.active && doc.needsReview).toList();
    final readyDocuments =
        documents.where((doc) => doc.active && doc.reviewed).toList();
    final uploadedDocuments = documents
        .where((doc) => doc.active && !doc.reviewed && !doc.needsReview)
        .toList();

    return ArthScaffold(
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 2,
        onTap: (i) => goToArthTab(context, i),
      ),
      child: Column(
        children: [
          ArthPremiumAppBar(
            eyebrow: activeYear.fyLabel,
            title: 'Vault',
            actions: [
              IconButton(
                tooltip: 'AIS guide',
                onPressed: () => context.push('/ais-guide'),
                icon: const Icon(Icons.account_balance_outlined),
                color: PaycheckColors.textSecondary,
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(taxDocumentProvider.notifier).refresh(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _VaultSummary(
                      percent: percent,
                      summary: summary,
                      remaining: remainingCount,
                    ),
                    const SizedBox(height: 24),
                    _VaultSectionHeader(
                      title: 'Needed documents',
                      helper: '$remainingCount remaining',
                    ),
                    const SizedBox(height: 12),
                    _NeededDocumentsPanel(
                      items: neededItems,
                      checklist: checklist,
                      busy: documentsAsync.isLoading,
                      onReady: (item, value) => ref
                          .read(documentChecklistProvider.notifier)
                          .setReady(item.id, value),
                      onUpload: (item) =>
                          _showUploadPreflight(context, ref, item),
                    ),
                    if (documents.isEmpty) ...[
                      const SizedBox(height: 24),
                      const _EmptyUploads(),
                    ],
                    if (reviewDocuments.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _DocumentLane(
                        title: 'Needs review',
                        documents: reviewDocuments,
                        onOpen: (doc) => _showDocumentDetail(context, ref, doc),
                      ),
                    ],
                    if (readyDocuments.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _DocumentLane(
                        title: 'Ready to use',
                        documents: readyDocuments,
                        onOpen: (doc) => _showDocumentDetail(context, ref, doc),
                      ),
                    ],
                    if (uploadedDocuments.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _DocumentLane(
                        title: 'Processing',
                        documents: uploadedDocuments,
                        onOpen: (doc) => _showDocumentDetail(context, ref, doc),
                      ),
                    ],
                    if (summary.archived > 0) ...[
                      const SizedBox(height: 24),
                      _DocumentLane(
                        title: 'Archived',
                        documents:
                            documents.where((doc) => doc.archived).toList(),
                        onOpen: (doc) => _showDocumentDetail(context, ref, doc),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TaxDocument> _documentsFor(String type, List<TaxDocument> documents) {
    return documents
        .where((doc) => doc.documentType == type && doc.active)
        .toList();
  }

  Future<void> _showUploadPreflight(
    BuildContext context,
    WidgetRef ref,
    TaxDocumentItem item,
  ) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PaycheckColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: PaycheckColors.border,
                    borderRadius: AppRadius.pill,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Upload ${item.title}', style: PaycheckType.h2()),
              const SizedBox(height: 8),
              Text(
                'Choose a PDF, JPG or PNG up to 8 MB. You can review extracted details before using them.',
                style:
                    PaycheckType.caption(color: PaycheckColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    color: PaycheckColors.gold,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'PDF · JPG · PNG   Maximum 8 MB',
                      style: PaycheckType.caption(
                        color: PaycheckColors.textPrimary,
                      ).copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: AppButtons.primaryGold,
                onPressed: () => Navigator.pop(sheetContext, true),
                icon: const Icon(Icons.upload_file_rounded, size: 19),
                label: const Text('Choose file'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
    if (accepted == true && context.mounted) {
      await _pickAndUpload(context, ref, item);
    }
  }

  Future<void> _pickAndUpload(
    BuildContext context,
    WidgetRef ref,
    TaxDocumentItem item,
  ) async {
    const typeGroup = XTypeGroup(
      label: 'Tax documents',
      extensions: ['pdf', 'jpg', 'jpeg', 'png'],
      mimeTypes: ['application/pdf', 'image/jpeg', 'image/png'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;

    List<int> uploadBytes = bytes;
    var uploadFilename = file.name;
    final detectedMimeType = _mimeType(file.name);
    if (detectedMimeType == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Use PDF, JPG, or PNG only.')),
        );
      }
      return;
    }
    var uploadMimeType = detectedMimeType;
    String? ocrText;
    if (item.id == 'payslip' && uploadMimeType.startsWith('image/')) {
      final ocr = OnDeviceDocumentOcrService();
      try {
        final prepared = await ocr.prepareForUploadAsync(
          bytes: bytes,
          filename: file.name,
        );
        uploadBytes = prepared.bytes;
        uploadFilename = prepared.filename;
        uploadMimeType = prepared.mimeType;
        ocrText = await ocr.extractLatinTextFromPreparedImage(prepared);
      } catch (_) {
        // Upload still provides manual review when preparation or OCR fails.
      }
    }
    if (uploadBytes.length > 8 * 1024 * 1024) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not reduce this image below 8 MB.'),
          ),
        );
      }
      return;
    }

    try {
      final uploaded = await ref.read(taxDocumentProvider.notifier).upload(
            documentType: item.id,
            filename: uploadFilename,
            mimeType: uploadMimeType,
            bytes: uploadBytes,
            ocrText: ocrText,
          );
      await ref
          .read(documentChecklistProvider.notifier)
          .setReady(item.id, true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.title} uploaded securely.')),
        );
        if (uploaded.needsConfirmation ||
            (uploaded.isPayslip && uploaded.extractedFields.isEmpty)) {
          _showDocumentDetail(context, ref, uploaded);
        }
      }
    } catch (error) {
      final message = error is ServerApiException
          ? error.message
          : 'Upload failed. Check connection and try again.';
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  String? _mimeType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    return null;
  }

  void _showDocumentDetail(
    BuildContext context,
    WidgetRef ref,
    TaxDocument document,
  ) {
    final labelController = TextEditingController(text: document.userLabel);
    final notesController = TextEditingController(text: document.notes);
    final tagsController =
        TextEditingController(text: document.tags.join(', '));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PaycheckColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        var saving = false;
        String? error;
        return StatefulBuilder(
          builder: (_, setSheetState) {
            Future<void> saveMetadata({
              String? vaultStatus,
              String? reviewStatus,
            }) async {
              setSheetState(() {
                saving = true;
                error = null;
              });
              try {
                await ref.read(taxDocumentProvider.notifier).updateMetadata(
                      document.id,
                      userLabel: labelController.text.trim(),
                      notes: notesController.text.trim(),
                      tags: tagsController.text
                          .split(',')
                          .map((tag) => tag.trim())
                          .where((tag) => tag.isNotEmpty)
                          .take(12)
                          .toList(),
                      vaultStatus: vaultStatus,
                      reviewStatus: reviewStatus,
                    );
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } catch (caught) {
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  saving = false;
                  error = caught is ServerApiException
                      ? caught.message
                      : 'Could not update document.';
                });
              }
            }

            Future<void> confirmFields() async {
              setSheetState(() {
                saving = true;
                error = null;
              });
              try {
                final confirmed = await ref
                    .read(taxDocumentProvider.notifier)
                    .confirmParsedFields(document.id);
                final documents = ref.read(taxDocumentProvider).asData?.value ??
                    <TaxDocument>[confirmed];
                ref.read(paycheckProvider.notifier).syncDocuments(documents);
                if (confirmed.documentType == 'offerLetter' &&
                    !confirmed.isPayslip) {
                  ref
                      .read(userProfileProvider.notifier)
                      .applyConfirmedOfferLetter(confirmed.confirmedFields);
                }
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      document.isPayslip
                          ? 'Payslip confirmed. Home is updated.'
                          : 'Document details confirmed.',
                    ),
                  ),
                );
              } catch (caught) {
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  saving = false;
                  error = caught is ServerApiException
                      ? caught.message
                      : 'Could not confirm fields.';
                });
              }
            }

            Future<void> deleteDocument() async {
              final shouldDelete = await showDialog<bool>(
                    context: sheetContext,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Delete this file permanently?'),
                      content: Text(
                        '${document.displayName} and its extracted details will be removed. This cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (!shouldDelete || !sheetContext.mounted) return;
              setSheetState(() => saving = true);
              try {
                await ref
                    .read(taxDocumentProvider.notifier)
                    .delete(document.id);
                final documents =
                    ref.read(taxDocumentProvider).asData?.value ?? const [];
                ref.read(paycheckProvider.notifier).syncDocuments(documents);
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File deleted permanently.')),
                );
              } catch (caught) {
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  saving = false;
                  error = caught is ServerApiException
                      ? caught.message
                      : 'Could not delete document.';
                });
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(document.displayName, style: PaycheckType.h2()),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _statusPill(document),
                          StatusPill(
                            label: formatFileSize(document.byteSize),
                            icon: Icons.storage_outlined,
                            color: PaycheckColors.teal,
                          ),
                          if (document.archived)
                            const StatusPill(
                              label: 'Archived',
                              icon: Icons.archive_outlined,
                              color: PaycheckColors.amber,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: labelController,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'Document label',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tagsController,
                        decoration: const InputDecoration(
                          labelText: 'Tags',
                          hintText: 'salary, form16',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        maxLength: 1200,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ParserTimeline(document: document),
                      if (document.extractedFields.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          document.isPayslip
                              ? 'Check your payslip details'
                              : 'Check extracted details',
                          style: PaycheckType.h3(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Confirm only if these details match the document.',
                          style: PaycheckType.caption(
                            color: PaycheckColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _FriendlyExtractedFields(
                          fields: document.extractedFields,
                        ),
                      ],
                      if (document.isPayslip &&
                          document.extractedFields.isEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: PaycheckColors.info.withValues(alpha: 0.08),
                            borderRadius: AppRadius.card,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'No reliable details were found',
                                style: PaycheckType.bodyMedium(),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Enter the printed gross pay, deductions '
                                'and net pay.',
                                style: PaycheckType.caption(
                                  color: PaycheckColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                style: AppButtons.outlineGold,
                                onPressed: saving
                                    ? null
                                    : () {
                                        Navigator.pop(sheetContext);
                                        _showManualPayslipEditor(
                                          context,
                                          ref,
                                          document,
                                        );
                                      },
                                icon: const Icon(Icons.edit_note_outlined),
                                label: const Text('Enter payslip details'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style:
                              PaycheckType.caption(color: PaycheckColors.alert),
                        ),
                      ],
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: AppButtons.primaryGold,
                        onPressed: saving ? null : () => saveMetadata(),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          saving ? 'Saving...' : 'Save label and notes',
                        ),
                      ),
                      if (document.needsConfirmation) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          style: AppButtons.outlineGold,
                          onPressed: saving ? null : confirmFields,
                          icon: const Icon(Icons.fact_check_outlined),
                          label: Text(
                            document.isPayslip
                                ? 'Use these payslip details'
                                : 'Confirm these details',
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: AppButtons.outlineGold,
                        onPressed: saving
                            ? null
                            : () => saveMetadata(
                                  vaultStatus:
                                      document.archived ? 'active' : 'archived',
                                ),
                        icon: Icon(document.archived
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined),
                        label: Text(document.archived ? 'Restore' : 'Archive'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: saving ? null : deleteDocument,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete permanently'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showManualPayslipEditor(
    BuildContext context,
    WidgetRef ref,
    TaxDocument document,
  ) async {
    final confirmed = await showModalBottomSheet<TaxDocument>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PaycheckColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _ManualPayslipEditor(
        onConfirm: (fields) => ref
            .read(taxDocumentProvider.notifier)
            .confirmParsedFields(document.id, fields: fields),
      ),
    );
    if (confirmed == null || !context.mounted) return;
    final documents =
        ref.read(taxDocumentProvider).asData?.value ?? <TaxDocument>[confirmed];
    ref.read(paycheckProvider.notifier).syncDocuments(documents);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payslip saved. Home is updated.')),
    );
  }
}

class _ManualPayslipEditor extends StatefulWidget {
  const _ManualPayslipEditor({required this.onConfirm});

  final Future<TaxDocument> Function(Map<String, dynamic> fields) onConfirm;

  @override
  State<_ManualPayslipEditor> createState() => _ManualPayslipEditorState();
}

class _ManualPayslipEditorState extends State<_ManualPayslipEditor> {
  final _employer = TextEditingController();
  final _payPeriod = TextEditingController();
  final _gross = TextEditingController();
  final _deductions = TextEditingController();
  final _net = TextEditingController();
  final List<_ManualPayRowControllers> _earnings = [];
  final List<_ManualPayRowControllers> _deductionRows = [];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _employer.dispose();
    _payPeriod.dispose();
    _gross.dispose();
    _deductions.dispose();
    _net.dispose();
    for (final row in [..._earnings, ..._deductionRows]) {
      row.dispose();
    }
    super.dispose();
  }

  double? _amount(TextEditingController controller) {
    return double.tryParse(controller.text.replaceAll(',', '').trim());
  }

  Map<String, dynamic>? _fields() {
    final gross = _amount(_gross);
    final deductions = _amount(_deductions);
    final net = _amount(_net);
    if (gross == null || gross <= 0) {
      _error = 'Enter the printed gross earnings.';
      return null;
    }
    if (deductions == null || deductions < 0) {
      _error = 'Enter total deductions. Use 0 if none are printed.';
      return null;
    }
    if (net == null || net <= 0) {
      _error = 'Enter the printed net salary.';
      return null;
    }
    if ((gross - deductions - net).abs() > 1) {
      _error = 'Gross minus deductions must equal net salary.';
      return null;
    }
    List<Map<String, dynamic>> rows(
      List<_ManualPayRowControllers> controllers,
    ) {
      return controllers
          .where((row) =>
              row.label.text.trim().isNotEmpty ||
              row.amount.text.trim().isNotEmpty)
          .map((row) {
        final amount = _amount(row.amount);
        if (row.label.text.trim().isEmpty || amount == null) {
          throw const FormatException();
        }
        return {
          'label': row.label.text.trim(),
          'amount': amount,
          'classification': 'other',
          'confidence': 'high',
        };
      }).toList();
    }

    try {
      return {
        'employerName':
            _employer.text.trim().isEmpty ? null : _employer.text.trim(),
        'employeeName': null,
        'payPeriod':
            _payPeriod.text.trim().isEmpty ? null : _payPeriod.text.trim(),
        'paymentDate': null,
        'currency': 'INR',
        'attendance': {
          'actualPayableDays': null,
          'totalWorkingDays': null,
          'lossOfPayDays': null,
          'daysPayable': null,
        },
        'earnings': rows(_earnings),
        'deductions': rows(_deductionRows),
        'grossEarnings': gross,
        'totalDeductions': deductions,
        'netSalary': net,
        'warnings': ['Entered manually by the user.'],
        'questionsForUser': <String>[],
      };
    } on FormatException {
      _error = 'Each added row needs a label and a valid amount.';
      return null;
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final fields = _fields();
    if (fields == null) {
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    try {
      final confirmed = await widget.onConfirm(fields);
      if (mounted) Navigator.pop(context, confirmed);
    } catch (caught) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = caught is ServerApiException
            ? caught.message
            : 'Could not save payslip details.';
      });
    }
  }

  void _addRow(List<_ManualPayRowControllers> rows) {
    setState(() => rows.add(_ManualPayRowControllers()));
  }

  void _removeRow(
    List<_ManualPayRowControllers> rows,
    _ManualPayRowControllers row,
  ) {
    setState(() => rows.remove(row));
    row.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final numberFormatters = <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter payslip details', style: PaycheckType.h2()),
              const SizedBox(height: 8),
              Text(
                'Use the monthly printed totals. Do not use cumulative or year-to-date values.',
                style:
                    PaycheckType.caption(color: PaycheckColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _employer,
                decoration:
                    const InputDecoration(labelText: 'Employer (optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _payPeriod,
                decoration:
                    const InputDecoration(labelText: 'Pay period (optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _gross,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: numberFormatters,
                decoration: const InputDecoration(labelText: 'Gross earnings'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _deductions,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: numberFormatters,
                decoration:
                    const InputDecoration(labelText: 'Total deductions'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _net,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: numberFormatters,
                decoration: const InputDecoration(labelText: 'Net salary'),
              ),
              const SizedBox(height: 20),
              _ManualPayRows(
                title: 'Earnings',
                rows: _earnings,
                formatters: numberFormatters,
                onAdd: () => _addRow(_earnings),
                onRemove: (row) => _removeRow(_earnings, row),
              ),
              const SizedBox(height: 16),
              _ManualPayRows(
                title: 'Deductions',
                rows: _deductionRows,
                formatters: numberFormatters,
                onAdd: () => _addRow(_deductionRows),
                onRemove: (row) => _removeRow(_deductionRows, row),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: PaycheckType.caption(color: PaycheckColors.alert),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: AppButtons.primaryGold,
                onPressed: _saving ? null : _submit,
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(_saving ? 'Saving...' : 'Save payslip'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualPayRowControllers {
  final label = TextEditingController();
  final amount = TextEditingController();

  void dispose() {
    label.dispose();
    amount.dispose();
  }
}

class _ManualPayRows extends StatelessWidget {
  const _ManualPayRows({
    required this.title,
    required this.rows,
    required this.formatters,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final List<_ManualPayRowControllers> rows;
  final List<TextInputFormatter> formatters;
  final VoidCallback onAdd;
  final ValueChanged<_ManualPayRowControllers> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: PaycheckType.bodyMedium())),
            IconButton(
              tooltip: 'Add ${title.toLowerCase()} row',
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: row.label,
                    decoration: const InputDecoration(labelText: 'Label'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: row.amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: formatters,
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove row',
                  onPressed: () => onRemove(row),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FriendlyExtractedFields extends StatelessWidget {
  const _FriendlyExtractedFields({required this.fields});

  final Map<String, dynamic> fields;

  static const _labels = <String, String>{
    'employerName': 'Employer',
    'employeeName': 'Employee',
    'roleTitle': 'Role',
    'payPeriod': 'Pay period',
    'paymentDate': 'Payment date',
    'currency': 'Currency',
    'annualCtc': 'Annual CTC',
    'fixedAnnualPay': 'Fixed annual pay',
    'variableAnnualPay': 'Variable annual pay',
    'joiningBonus': 'Joining bonus',
    'grossEarnings': 'Gross earnings',
    'totalDeductions': 'Total deductions',
    'netSalary': 'Net salary',
    'actualPayableDays': 'Actual payable days',
    'totalWorkingDays': 'Total working days',
    'lossOfPayDays': 'Loss of pay days',
    'daysPayable': 'Days payable',
  };

  static const _moneyKeys = <String>{
    'annualCtc',
    'fixedAnnualPay',
    'variableAnnualPay',
    'joiningBonus',
    'grossEarnings',
    'totalDeductions',
    'netSalary',
  };

  @override
  Widget build(BuildContext context) {
    final scalars = fields.entries.where(
      (entry) => entry.value is! List && entry.value is! Map,
    );
    final attendance = _map('attendance');
    final earnings = _rows('earnings');
    final deductions = _rows('deductions');
    final cumulative = _rows('cumulative');
    final components = _rows('components');
    final warnings = _strings('warnings');
    final questions = _strings('questionsForUser');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in scalars)
          if (entry.key != 'warnings' && entry.key != 'questionsForUser')
            _ParsedFieldRow(
              label: _label(entry.key),
              value: _value(entry.key, entry.value),
            ),
        if (attendance.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Attendance', style: PaycheckType.bodyMedium()),
          const SizedBox(height: 8),
          for (final entry in attendance.entries)
            _ParsedFieldRow(
              label: _label(entry.key),
              value: entry.value?.toString() ?? 'Not found',
            ),
        ],
        if (earnings.isNotEmpty) _amountSection('Earnings', earnings, 'amount'),
        if (deductions.isNotEmpty)
          _amountSection('Deductions', deductions, 'amount'),
        if (cumulative.isNotEmpty)
          _amountSection('Cumulative / year to date', cumulative, 'amount'),
        if (components.isNotEmpty)
          _amountSection('Pay components', components, 'annualAmount'),
        if (warnings.isNotEmpty)
          _messageSection(
            'Check before confirming',
            warnings,
            PaycheckColors.amber.withValues(alpha: 0.12),
          ),
        if (questions.isNotEmpty)
          _messageSection(
            'Details ARTH could not confirm',
            questions,
            PaycheckColors.info.withValues(alpha: 0.10),
          ),
      ],
    );
  }

  Widget _amountSection(
    String title,
    List<Map<String, dynamic>> rows,
    String amountKey,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: PaycheckType.bodyMedium()),
          const SizedBox(height: 8),
          for (final row in rows)
            _ParsedFieldRow(
              label: row['label']?.toString() ?? 'Item',
              value: row[amountKey] is num
                  ? formatRupeesCompact((row[amountKey] as num).round())
                  : 'Amount not found',
            ),
        ],
      ),
    );
  }

  Widget _messageSection(String title, List<String> messages, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color, borderRadius: AppRadius.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: PaycheckType.bodyMedium()),
          const SizedBox(height: 4),
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '• $message',
                style:
                    PaycheckType.caption(color: PaycheckColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Map<String, dynamic> _map(String key) =>
      fields[key] as Map<String, dynamic>? ?? const {};

  List<Map<String, dynamic>> _rows(String key) =>
      (fields[key] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

  List<String> _strings(String key) =>
      (fields[key] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false);

  String _label(String key) =>
      _labels[key] ??
      key.replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)!.toLowerCase()}',
      );

  String _value(String key, Object? value) {
    if (value == null) return 'Not found';
    if (_moneyKeys.contains(key) && value is num) {
      return formatRupeesCompact(value.round());
    }
    return value.toString();
  }
}

class _VaultSummary extends StatelessWidget {
  final int percent;
  final DocumentVaultSummary summary;
  final int remaining;

  const _VaultSummary({
    required this.percent,
    required this.summary,
    required this.remaining,
  });

  @override
  Widget build(BuildContext context) {
    final message = remaining == 0
        ? 'Your proof checklist is complete.'
        : '$remaining proof ${remaining == 1 ? 'item' : 'items'} still need attention.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: PaycheckType.h1().copyWith(fontSize: 32, height: 1.08),
        ),
        const SizedBox(height: 16),
        Text(
          '${summary.active} uploaded · ${summary.needsReview} need review',
          style: PaycheckType.caption(color: PaycheckColors.textSecondary),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: AppRadius.pill,
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 4,
            backgroundColor: PaycheckColors.surfaceMuted,
            valueColor: const AlwaysStoppedAnimation(PaycheckColors.primary),
          ),
        ),
      ],
    );
  }
}

class VaultHero extends StatelessWidget {
  final int percent;
  final DocumentVaultSummary summary;
  final String yearLabel;

  const VaultHero({
    super.key,
    required this.percent,
    required this.summary,
    required this.yearLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: PaycheckColors.bgCard,
        borderRadius: AppRadius.card,
        border: Border.fromBorderSide(BorderSide(color: PaycheckColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            height: 68,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: percent / 100,
                  strokeWidth: 7,
                  backgroundColor: PaycheckColors.bgSurface,
                  color: percent == 100
                      ? PaycheckColors.success
                      : PaycheckColors.gold,
                  strokeCap: StrokeCap.round,
                ),
                Text('$percent%', style: PaycheckType.bodyMedium()),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Proof readiness', style: PaycheckType.h3()),
                const SizedBox(height: 4),
                Text(
                  '$yearLabel · ${summary.active} uploaded · ${summary.needsReview} to review',
                  style:
                      PaycheckType.caption(color: PaycheckColors.textSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  percent == 100
                      ? 'Your document checklist is complete.'
                      : 'Add proofs as you collect them.',
                  style: PaycheckType.micro(color: PaycheckColors.gold)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VaultSectionHeader extends StatelessWidget {
  final String title;
  final String? helper;

  const _VaultSectionHeader({
    required this.title,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: PaycheckType.h3())),
        if (helper != null)
          Text(
            helper!,
            style: PaycheckType.micro(color: PaycheckColors.textSecondary),
          ),
      ],
    );
  }
}

class _DocumentLane extends StatelessWidget {
  final String title;
  final List<TaxDocument> documents;
  final ValueChanged<TaxDocument> onOpen;

  const _DocumentLane({
    required this.title,
    required this.documents,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VaultSectionHeader(title: title, helper: '${documents.length}'),
        const SizedBox(height: 12),
        for (final document in documents) ...[
          DocumentStatusCard(
            document: document,
            onTap: () => onOpen(document),
          ),
          if (document != documents.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _NeededDocumentsPanel extends StatelessWidget {
  final List<TaxDocumentItem> items;
  final Map<String, bool> checklist;
  final bool busy;
  final void Function(TaxDocumentItem item, bool value) onReady;
  final ValueChanged<TaxDocumentItem> onUpload;

  const _NeededDocumentsPanel({
    required this.items,
    required this.checklist,
    required this.busy,
    required this.onReady,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: PaycheckColors.goldLight,
          borderRadius: AppRadius.card,
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: PaycheckColors.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Every expected document has been added.',
                style: PaycheckType.bodyMedium(),
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: PaycheckColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: PaycheckColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final entry in items.asMap().entries) ...[
            _NeededDocumentRow(
              item: entry.value,
              ready: checklist[entry.value.id] ?? false,
              busy: busy,
              onReady: (value) => onReady(entry.value, value),
              onUpload: () => onUpload(entry.value),
            ),
            if (entry.key != items.length - 1)
              const Divider(height: 1, indent: 58),
          ],
        ],
      ),
    );
  }
}

class _NeededDocumentRow extends StatelessWidget {
  final TaxDocumentItem item;
  final bool ready;
  final bool busy;
  final ValueChanged<bool> onReady;
  final VoidCallback onUpload;

  const _NeededDocumentRow({
    required this.item,
    required this.ready,
    required this.busy,
    required this.onReady,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          Checkbox(
            value: ready,
            onChanged: (value) => onReady(value ?? false),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: PaycheckType.bodyMedium()),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      PaycheckType.caption(color: PaycheckColors.textSecondary),
                ),
                if (ready) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Marked ready',
                    style: PaycheckType.micro(color: PaycheckColors.success),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Upload ${item.title}',
            onPressed: busy ? null : onUpload,
            icon: const Icon(Icons.upload_file_rounded),
            color: PaycheckColors.gold,
          ),
        ],
      ),
    );
  }
}

class _EmptyUploads extends StatelessWidget {
  const _EmptyUploads();

  @override
  Widget build(BuildContext context) {
    return const ArthInlineEmpty(
      icon: Icons.folder_open_outlined,
      title: 'No uploads yet',
      message: 'Use the upload icon beside any document to begin.',
    );
  }
}

class DocumentStatusCard extends StatelessWidget {
  final TaxDocument document;
  final VoidCallback onTap;

  const DocumentStatusCard({
    super.key,
    required this.document,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PaycheckColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(
          color: _statusColor(document).withValues(alpha: 0.32),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.description_outlined, color: _statusColor(document)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PaycheckType.bodyMedium(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatFileSize(document.byteSize)} • ${document.originalFilename}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PaycheckType.micro(
                          color: PaycheckColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statusPill(document),
                        for (final tag in document.tags.take(3))
                          StatusPill(
                            label: tag,
                            icon: Icons.sell_outlined,
                            color: PaycheckColors.info,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  color: PaycheckColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParserTimeline extends StatelessWidget {
  final TaxDocument document;

  const _ParserTimeline({required this.document});

  @override
  Widget build(BuildContext context) {
    final insight = document.parseSummary['insight'] as String? ??
        'Stored in encrypted document vault.';
    return PremiumGlassPanel(
      padding: const EdgeInsets.all(16),
      tint: _statusColor(document),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Parser timeline', style: PaycheckType.h3()),
          const SizedBox(height: 12),
          const _TimelineRow(
            done: true,
            title: 'Stored encrypted',
            body: 'File encrypted and stored in ARTH vault.',
          ),
          _TimelineRow(
            done: document.parseStatus != 'metadata_ready',
            title: document.parseStatusLabel,
            body: insight,
          ),
          _TimelineRow(
            done: document.reviewed,
            title: 'User confirmed',
            body: 'Kept separate from parser metadata. Never changes '
                'tax calculations silently.',
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final bool done;
  final String title;
  final String body;

  const _TimelineRow({
    required this.done,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: done ? PaycheckColors.success : PaycheckColors.textMuted,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PaycheckType.bodyMedium()),
                const SizedBox(height: 4),
                Text(
                  body,
                  style:
                      PaycheckType.micro(color: PaycheckColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParsedFieldRow extends StatelessWidget {
  final String label;
  final String value;

  const _ParsedFieldRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: PaycheckType.caption(color: PaycheckColors.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: PaycheckType.bodyMedium(),
            ),
          ),
        ],
      ),
    );
  }
}

StatusPill _statusPill(TaxDocument document) {
  return StatusPill(
    label: document.parseStatusLabel,
    icon: document.reviewed
        ? Icons.verified_outlined
        : document.needsReview
            ? Icons.rate_review_outlined
            : Icons.lock_outline_rounded,
    color: _statusColor(document),
  );
}

Color _statusColor(TaxDocument document) {
  if (document.reviewed) return PaycheckColors.success;
  if (document.needsReview) return PaycheckColors.amber;
  if (document.unsupported) return PaycheckColors.alert;
  return PaycheckColors.teal;
}
