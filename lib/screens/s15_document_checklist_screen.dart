import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/tax_document.dart';
import '../models/tax_readiness.dart';
import '../providers/tax_document_provider.dart';
import '../providers/tax_readiness_provider.dart';
import '../services/server_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';

class DocumentChecklistScreen extends ConsumerWidget {
  const DocumentChecklistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checklist = ref.watch(documentChecklistProvider);
    final documentsAsync = ref.watch(taxDocumentProvider);
    final ready = completedDocumentCount(checklist);
    final total = taxDocumentItems.length;
    final percent = documentReadinessPercent(checklist);

    return ArthScaffold(
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 1,
        onTap: (i) {
          switch (i) {
            case 0:
              context.go('/discover');
              break;
            case 1:
              context.go('/action-plan');
              break;
            case 2:
              context.go('/progress');
              break;
            case 3:
              context.go('/profile');
              break;
          }
        },
      ),
      child: Column(
        children: [
          ArthPremiumAppBar(
            eyebrow: 'Actions',
            title: 'Document checklist',
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PremiumGlassPanel(
                    elevated: true,
                    borderRadius: BorderRadius.circular(28),
                    tint: AppColors.gold,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TrustBadge(
                          icon: Icons.folder_copy_outlined,
                          label: 'Encrypted vault',
                        ),
                        const SizedBox(height: 16),
                        Text('$ready/$total ready', style: AppTextStyles.h1()),
                        const SizedBox(height: 8),
                        Text(
                          'Track proof readiness and upload optional PDFs or images into an encrypted server vault.',
                          style: AppTextStyles.body(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: AppRadius.pill,
                          child: LinearProgressIndicator(
                            value: total == 0 ? 0 : ready / total,
                            minHeight: 9,
                            backgroundColor: AppColors.bgSurface,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              percent == 100
                                  ? AppColors.success
                                  : AppColors.gold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ArthSection(
                    title: 'Proof readiness',
                    child: Column(
                      children: taxDocumentItems.map((item) {
                        final uploaded = documentsAsync.asData?.value
                                .where((doc) => doc.documentType == item.id)
                                .toList() ??
                            const <TaxDocument>[];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DocumentTile(
                            item: item,
                            ready: checklist[item.id] ?? false,
                            documents: uploaded,
                            busy: documentsAsync.isLoading,
                            onChanged: (value) => ref
                                .read(documentChecklistProvider.notifier)
                                .setReady(item.id, value),
                            onUpload: () => _pickAndUpload(context, ref, item),
                            onDelete: (id) => ref
                                .read(taxDocumentProvider.notifier)
                                .delete(id),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ArthSection(
                    title: 'Filing handoff',
                    child: PremiumGlassPanel(
                      child: Column(
                        children: const [
                          _HandoffRow(
                            icon: Icons.rule_folder_outlined,
                            title: 'Review Form 16 and deductions',
                            body:
                                'Match employer data with the diagnostic before filing.',
                          ),
                          Divider(color: AppColors.divider),
                          _HandoffRow(
                            icon: Icons.account_balance_outlined,
                            title: 'Check AIS and 26AS',
                            body:
                                'Confirm TDS, interest, dividends, and tax payments.',
                          ),
                          Divider(color: AppColors.divider),
                          _HandoffRow(
                            icon: Icons.handshake_outlined,
                            title: 'Hand off to portal or CA',
                            body:
                                'ARTH stores your proofs securely and prepares your view. It does not file ITR in this version.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
}

class _DocumentTile extends StatelessWidget {
  final TaxDocumentItem item;
  final bool ready;
  final List<TaxDocument> documents;
  final bool busy;
  final ValueChanged<bool> onChanged;
  final VoidCallback onUpload;
  final ValueChanged<String> onDelete;

  const _DocumentTile({
    required this.item,
    required this.ready,
    required this.documents,
    required this.busy,
    required this.onChanged,
    required this.onUpload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
      padding: const EdgeInsets.all(14),
      tint: ready ? AppColors.success : Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: ready,
            onChanged: (value) => onChanged(value ?? false),
            activeColor: AppColors.success,
            checkColor: Colors.white,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: AppTextStyles.bodyMedium()),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  item.whyItMatters,
                  style: AppTextStyles.micro(color: AppColors.gold),
                ),
                const SizedBox(height: 10),
                if (documents.isEmpty)
                  OutlinedButton.icon(
                    style: AppButtons.outlineGold,
                    onPressed: busy ? null : onUpload,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Upload securely'),
                  )
                else ...[
                  ...documents.map(
                    (doc) => _UploadedDocumentRow(
                      document: doc,
                      onDelete: () => onDelete(doc.id),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: busy ? null : onUpload,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add another'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadedDocumentRow extends StatelessWidget {
  final TaxDocument document;
  final VoidCallback onDelete;

  const _UploadedDocumentRow({
    required this.document,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final insight = document.parseSummary['insight'] as String? ??
        'Stored in encrypted document vault.';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bgSurface.withValues(alpha: 0.55),
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded,
              color: AppColors.teal, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.originalFilename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatFileSize(document.byteSize)} • ${document.parseStatus}',
                  style: AppTextStyles.micro(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  insight,
                  style: AppTextStyles.micro(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete document',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppColors.alert,
          ),
        ],
      ),
    );
  }
}

class _HandoffRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _HandoffRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.teal, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyMedium()),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
