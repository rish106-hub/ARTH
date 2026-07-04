import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/tax_document.dart';
import '../models/tax_readiness.dart';
import '../providers/tax_document_provider.dart';
import '../providers/tax_readiness_provider.dart';
import '../providers/tax_year_provider.dart';
import '../services/server_api_service.dart';
import '../theme/app_theme.dart';
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

    return ArthScaffold(
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 1,
        onTap: (i) => goToArthTab(context, i),
      ),
      child: Column(
        children: [
          ArthPremiumAppBar(
            eyebrow: 'Vault',
            title: 'Document Vault',
            actions: [
              IconButton(
                tooltip: 'AIS guide',
                onPressed: () => context.push('/ais-guide'),
                icon: const Icon(Icons.account_balance_outlined),
                color: AppColors.textSecondary,
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(taxDocumentProvider.notifier).refresh(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    VaultHero(
                      percent: percent,
                      summary: summary,
                      yearLabel: activeYear.fyLabel,
                    ),
                    const SizedBox(height: 18),
                    _VaultLane(
                      title: 'Needs action',
                      icon: Icons.inbox_outlined,
                      child: Column(
                        children: [
                          for (final item in taxDocumentItems)
                            if (_documentsFor(item.id, documents).isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _NeededDocumentCard(
                                  item: item,
                                  ready: checklist[item.id] ?? false,
                                  busy: documentsAsync.isLoading,
                                  onReady: (value) => ref
                                      .read(documentChecklistProvider.notifier)
                                      .setReady(item.id, value),
                                  onUpload: () =>
                                      _showUploadPreflight(context, ref, item),
                                ),
                              ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _DocumentLane(
                      title: 'Review',
                      empty: 'No documents need review.',
                      documents: documents
                          .where((doc) => doc.active && doc.needsReview)
                          .toList(),
                      onOpen: (doc) => _showDocumentDetail(context, ref, doc),
                    ),
                    const SizedBox(height: 16),
                    _DocumentLane(
                      title: 'Ready',
                      empty: 'Confirmed documents will appear here.',
                      documents: documents
                          .where((doc) => doc.active && doc.reviewed)
                          .toList(),
                      onOpen: (doc) => _showDocumentDetail(context, ref, doc),
                    ),
                    const SizedBox(height: 16),
                    _DocumentLane(
                      title: 'Uploaded',
                      empty: 'Upload a proof to start building your vault.',
                      documents: documents
                          .where((doc) =>
                              doc.active && !doc.reviewed && !doc.needsReview)
                          .toList(),
                      onOpen: (doc) => _showDocumentDetail(context, ref, doc),
                    ),
                    if (summary.archived > 0) ...[
                      const SizedBox(height: 16),
                      _DocumentLane(
                        title: 'Archived',
                        empty: '',
                        documents:
                            documents.where((doc) => doc.archived).toList(),
                        onOpen: (doc) => _showDocumentDetail(context, ref, doc),
                      ),
                    ],
                    const SizedBox(height: 16),
                    StoryPanel(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy posture',
                      body:
                          'Documents are encrypted on the server. ARTH stores metadata and confirmed fields separately, and never files ITR from this vault.',
                      color: AppColors.teal,
                    ),
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
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Upload ${item.title}', style: AppTextStyles.h2()),
              const SizedBox(height: 8),
              Text(
                'PDF, JPG, or PNG up to 8 MB. Text PDFs can be parsed deterministically when supported. Scans and password files are stored for manual review.',
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(
                    label: 'Encrypted storage',
                    icon: Icons.lock_outline_rounded,
                    color: AppColors.teal,
                  ),
                  StatusPill(
                    label: 'No LLM parsing',
                    icon: Icons.verified_user_outlined,
                  ),
                  StatusPill(
                    label: 'Hard delete available',
                    icon: Icons.delete_outline_rounded,
                    color: AppColors.amber,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ActionDock(
                primaryLabel: 'Choose file',
                primaryIcon: Icons.upload_file_rounded,
                onPrimary: () => Navigator.pop(sheetContext, true),
                secondaryLabel: 'Cancel',
                secondaryIcon: Icons.close_rounded,
                onSecondary: () => Navigator.pop(sheetContext, false),
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

    final mimeType = _mimeType(file.name);
    if (mimeType == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Use PDF, JPG, or PNG only.')),
        );
      }
      return;
    }
    if (bytes.length > 8 * 1024 * 1024) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document must be under 8 MB.')),
        );
      }
      return;
    }

    try {
      await ref.read(taxDocumentProvider.notifier).upload(
            documentType: item.id,
            filename: file.name,
            mimeType: mimeType,
            bytes: bytes,
          );
      await ref
          .read(documentChecklistProvider.notifier)
          .setReady(item.id, true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.title} uploaded securely.')),
        );
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
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        var saving = false;
        String? error;
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                await ref
                    .read(taxDocumentProvider.notifier)
                    .confirmParsedFields(document.id);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
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
              setSheetState(() => saving = true);
              try {
                await ref
                    .read(taxDocumentProvider.notifier)
                    .delete(document.id);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } catch (_) {
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  saving = false;
                  error = 'Could not delete document.';
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
                      Text(document.displayName, style: AppTextStyles.h2()),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _statusPill(document),
                          StatusPill(
                            label: formatFileSize(document.byteSize),
                            icon: Icons.storage_outlined,
                            color: AppColors.teal,
                          ),
                          if (document.archived)
                            const StatusPill(
                              label: 'Archived',
                              icon: Icons.archive_outlined,
                              color: AppColors.amber,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: labelController,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'Vault label',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: tagsController,
                        decoration: const InputDecoration(
                          labelText: 'Tags',
                          hintText: 'salary, form16',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        maxLength: 1200,
                        decoration: const InputDecoration(
                          labelText: 'Private note',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ParserTimeline(document: document),
                      if (document.extractedFields.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('Extracted fields', style: AppTextStyles.h3()),
                        const SizedBox(height: 8),
                        ...document.extractedFields.entries.map(
                          (entry) => _ParsedFieldRow(
                            label: _fieldLabel(entry.key),
                            value: _fieldValue(entry.value),
                          ),
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          error!,
                          style: AppTextStyles.caption(color: AppColors.alert),
                        ),
                      ],
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        style: AppButtons.primaryGold,
                        onPressed: saving ? null : () => saveMetadata(),
                        icon: const Icon(Icons.save_outlined),
                        label:
                            Text(saving ? 'Saving...' : 'Save vault details'),
                      ),
                      if (document.needsConfirmation) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          style: AppButtons.outlineGold,
                          onPressed: saving ? null : confirmFields,
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Confirm extracted fields'),
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

  String _fieldLabel(String key) {
    const labels = {
      'employerName': 'Employer',
      'employerTan': 'Employer TAN',
      'financialYear': 'Financial year',
      'assessmentYear': 'Assessment year',
      'grossSalary': 'Gross salary',
      'standardDeduction': 'Standard deduction',
      'chapterViaDeductions': 'Chapter VI-A deductions',
      'taxDeductedAtSource': 'TDS',
      'taxableIncome': 'Taxable income',
      'panMatchStatus': 'PAN match',
    };
    return labels[key] ?? key;
  }

  String _fieldValue(Object? value) {
    if (value is num) return formatRupeesCompact(value.round());
    if (value == 'matches_vault') return 'Matches PAN vault';
    if (value == 'differs_from_vault') return 'Differs from PAN vault';
    if (value == 'not_checked') return 'PAN vault not added';
    if (value == 'not_found') return 'Not found in text';
    return value?.toString() ?? '-';
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
    return PremiumHeader(
      eyebrow: 'Encrypted readiness',
      title: 'Your tax proof vault',
      body:
          '$yearLabel • ${summary.active} active document(s), ${summary.needsReview} needing review. Uploads stay optional and private.',
      icon: Icons.folder_special_outlined,
      trailing: SizedBox(
        width: 74,
        child: Column(
          children: [
            Text('$percent%', style: AppTextStyles.h2(color: AppColors.gold)),
            const SizedBox(height: 3),
            Text(
              'ready',
              textAlign: TextAlign.center,
              style: AppTextStyles.micro(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultLane extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _VaultLane({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ArthSection(
      title: title,
      child: PremiumGlassPanel(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}

class _DocumentLane extends StatelessWidget {
  final String title;
  final String empty;
  final List<TaxDocument> documents;
  final ValueChanged<TaxDocument> onOpen;

  const _DocumentLane({
    required this.title,
    required this.empty,
    required this.documents,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return _VaultLane(
      title: title,
      icon: Icons.folder_outlined,
      child: documents.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                empty,
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
            )
          : Column(
              children: [
                for (final document in documents)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DocumentStatusCard(
                      document: document,
                      onTap: () => onOpen(document),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _NeededDocumentCard extends StatelessWidget {
  final TaxDocumentItem item;
  final bool ready;
  final bool busy;
  final ValueChanged<bool> onReady;
  final VoidCallback onUpload;

  const _NeededDocumentCard({
    required this.item,
    required this.ready,
    required this.busy,
    required this.onReady,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard.withValues(alpha: 0.72),
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: ready,
            onChanged: (value) => onReady(value ?? false),
            activeColor: AppColors.success,
            checkColor: Colors.white,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: AppTextStyles.bodyMedium()),
                const SizedBox(height: 3),
                Text(
                  item.subtitle,
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusPill(
                      label: ready ? 'Marked ready' : 'Needed',
                      icon: ready
                          ? Icons.check_circle_outline_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: ready ? AppColors.success : AppColors.amber,
                    ),
                    OutlinedButton.icon(
                      style: AppButtons.outlineGold,
                      onPressed: busy ? null : onUpload,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Upload'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
    return InkWell(
      borderRadius: AppRadius.card,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgCard.withValues(alpha: 0.76),
          borderRadius: AppRadius.card,
          border:
              Border.all(color: _statusColor(document).withValues(alpha: 0.32)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline_rounded, color: _statusColor(document)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium(),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${formatFileSize(document.byteSize)} • ${document.originalFilename}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.micro(color: AppColors.textSecondary),
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
                          color: AppColors.info,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
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
      padding: const EdgeInsets.all(14),
      tint: _statusColor(document),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Parser timeline', style: AppTextStyles.h3()),
          const SizedBox(height: 10),
          _TimelineRow(
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
            body:
                'Confirmed fields are kept separate from parser metadata and do not update tax calculations silently.',
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: done ? AppColors.success : AppColors.textMuted,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyMedium()),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: AppTextStyles.micro(color: AppColors.textSecondary),
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
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTextStyles.bodyMedium(),
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
  if (document.reviewed) return AppColors.success;
  if (document.needsReview) return AppColors.amber;
  if (document.unsupported) return AppColors.alert;
  return AppColors.teal;
}
