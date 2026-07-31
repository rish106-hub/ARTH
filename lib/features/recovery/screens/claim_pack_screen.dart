import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/paycheck.dart';
import '../../../models/tax_document.dart';
import '../../../providers/paycheck_provider.dart';
import '../../../providers/tax_document_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/paycheck_theme.dart';
import '../models/recovery_models.dart';
import '../providers/recovery_provider.dart';
import '../services/claim_pack_service.dart';

class ClaimPackScreen extends ConsumerStatefulWidget {
  const ClaimPackScreen({super.key, required this.claimId});

  final String claimId;

  @override
  ConsumerState<ClaimPackScreen> createState() => _ClaimPackScreenState();
}

class _ClaimPackScreenState extends ConsumerState<ClaimPackScreen> {
  final _noteController = TextEditingController();
  final Set<String> _selected = {};
  bool _approved = false;
  bool _exporting = false;
  bool _initialized = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final documents = ref.watch(taxDocumentProvider);
    final paycheck = ref.watch(paycheckProvider);
    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: AppBar(
        backgroundColor: PaycheckColors.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text('Prepare claim', style: PaycheckType.heading()),
      ),
      body: recovery.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: 'Claim data could not be loaded.',
          onRetry: () => ref.invalidate(recoveryProvider),
        ),
        data: (state) {
          final claim = _findClaim(state);
          if (claim == null) {
            return const _ErrorState(
              message: 'This claim item is no longer available.',
            );
          }
          if (!_initialized) {
            _initialized = true;
            _noteController.text = claim.note;
            _selected.addAll(claim.selectedEvidenceIds);
          }
          return documents.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _ErrorState(
              message: 'Documents could not be loaded.',
              onRetry: () => ref.read(taxDocumentProvider.notifier).refresh(),
            ),
            data: (docs) => _ClaimPackBody(
              claim: claim,
              paycheck: paycheck,
              documents: docs.where((doc) => doc.active).toList(),
              selected: _selected,
              noteController: _noteController,
              approved: _approved,
              exporting: _exporting,
              onToggleEvidence: (id, selected) {
                setState(() {
                  if (selected) {
                    _selected.add(id);
                  } else {
                    _selected.remove(id);
                  }
                });
              },
              onApprovalChanged: (value) {
                setState(() => _approved = value);
              },
              onExport: () => _export(claim, paycheck, docs),
            ),
          );
        },
      ),
    );
  }

  ClaimCase? _findClaim(RecoveryState state) {
    for (final claim in state.claimCases) {
      if (claim.id == widget.claimId ||
          claim.paycheckItemId == widget.claimId) {
        return claim;
      }
    }
    return null;
  }

  Future<void> _export(
    ClaimCase claim,
    PaycheckState paycheck,
    List<TaxDocument> documents,
  ) async {
    if (_exporting) return;
    if (_selected.isEmpty || !_approved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select evidence and approve the summary first.'),
        ),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      final evidence = documents
          .where((document) => _selected.contains(document.id))
          .toList(growable: false);
      final downloads = <String, List<int>>{};
      for (final document in evidence) {
        downloads[document.id] =
            await ref.read(taxDocumentProvider.notifier).download(document.id);
      }
      final savedClaim = claim.copyWith(
        note: _noteController.text.trim(),
        selectedEvidenceIds: _selected.toList(growable: false),
      );
      final artifact = await const ClaimPackService().build(
        claim: savedClaim,
        paycheck: paycheck,
        evidence: evidence,
        evidenceBytes: downloads,
        userApproved: _approved,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              artifact.summaryPdf,
              mimeType: 'application/pdf',
              name: 'ARTH-claim-summary.pdf',
            ),
            XFile.fromData(
              artifact.bytes,
              mimeType: 'application/zip',
              name: artifact.filename,
            ),
          ],
          text:
              'Claim pack for ${claim.label}. Review all details before sending it to HR.',
        ),
      );
      await ref.read(recoveryProvider.notifier).updateClaim(
            claim.id,
            status: ClaimCaseStatus.prepared,
            note: _noteController.text.trim(),
            selectedEvidenceIds: _selected.toList(growable: false),
          );
      ref
          .read(paycheckProvider.notifier)
          .markClaimPrepared(claim.paycheckItemId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Claim pack prepared. Nothing was sent.')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError
          ? error.message
          : 'Could not prepare the claim pack. Try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class _ClaimPackBody extends StatelessWidget {
  const _ClaimPackBody({
    required this.claim,
    required this.paycheck,
    required this.documents,
    required this.selected,
    required this.noteController,
    required this.approved,
    required this.exporting,
    required this.onToggleEvidence,
    required this.onApprovalChanged,
    required this.onExport,
  });

  final ClaimCase claim;
  final PaycheckState paycheck;
  final List<TaxDocument> documents;
  final Set<String> selected;
  final TextEditingController noteController;
  final bool approved;
  final bool exporting;
  final void Function(String id, bool selected) onToggleEvidence;
  final ValueChanged<bool> onApprovalChanged;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          Text('CLAIM CASEFILE', style: PaycheckType.sectionLabel()),
          const SizedBox(height: 8),
          Text(claim.label, style: PaycheckType.h1()),
          const SizedBox(height: 4),
          Text(
            _money(claim.amount),
            style: PaycheckType.displaySmall(color: PaycheckColors.matched),
          ),
          const SizedBox(height: 18),
          _ClaimContextCard(claim: claim, paycheck: paycheck),
          const SizedBox(height: 24),
          Text('Evidence spine', style: PaycheckType.heading()),
          const SizedBox(height: 4),
          Text(
            'Choose files that prove this amount. ARTH downloads them only for this export.',
            style: PaycheckType.body(color: PaycheckColors.inkSoft),
          ),
          const SizedBox(height: 12),
          if (documents.isEmpty)
            _EmptyEvidence(onAdd: () => context.push('/documents'))
          else
            ...documents.asMap().entries.map(
                  (entry) => _EvidenceChoice(
                    index: entry.key,
                    document: entry.value,
                    selected: selected.contains(entry.value.id),
                    onChanged: (value) =>
                        onToggleEvidence(entry.value.id, value),
                  ),
                ),
          const SizedBox(height: 22),
          Text('Note for HR', style: PaycheckType.heading()),
          const SizedBox(height: 8),
          TextField(
            controller: noteController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Explain the mismatch or reimbursement request.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: approved,
            onChanged: (value) => onApprovalChanged(value == true),
            title: Text(
              'I checked the amount and selected evidence',
              style: PaycheckType.bodyStrong(),
            ),
            subtitle: Text(
              'ARTH prepares files. It does not send or submit the claim.',
              style: PaycheckType.utility(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('export_claim_pack'),
            onPressed:
                selected.isNotEmpty && approved && !exporting ? onExport : null,
            style: FilledButton.styleFrom(
              backgroundColor: PaycheckColors.ink,
              minimumSize: const Size.fromHeight(54),
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.control,
              ),
            ),
            icon: exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.archive_outlined),
            label: Text(
              exporting ? 'Preparing files' : 'Create PDF + ZIP',
              style: PaycheckType.bodyStrong(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClaimContextCard extends StatelessWidget {
  const _ClaimContextCard({required this.claim, required this.paycheck});

  final ClaimCase claim;
  final PaycheckState paycheck;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PaycheckColors.paper,
        border: Border.all(color: PaycheckColors.line),
        borderRadius: AppRadius.card,
      ),
      child: Column(
        children: [
          _ContextRow(label: 'Pay period', value: paycheck.payPeriod),
          _ContextRow(
            label: 'Employer',
            value: paycheck.employer.trim().isEmpty
                ? 'Not added'
                : paycheck.employer,
          ),
          _ContextRow(label: 'Reason', value: claim.detail, last: true),
        ],
      ),
    );
  }
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: PaycheckColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: PaycheckType.utility()),
          ),
          Expanded(child: Text(value, style: PaycheckType.bodyStrong())),
        ],
      ),
    );
  }
}

class _EvidenceChoice extends StatelessWidget {
  const _EvidenceChoice({
    required this.index,
    required this.document,
    required this.selected,
    required this.onChanged,
  });

  final int index;
  final TaxDocument document;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected ? PaycheckColors.matchedSoft : PaycheckColors.paper,
        border: Border.all(
          color: selected ? PaycheckColors.matched : PaycheckColors.line,
        ),
        borderRadius: AppRadius.card,
      ),
      child: CheckboxListTile(
        value: selected,
        onChanged: (value) => onChanged(value == true),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          '${index + 1}. ${document.displayName}',
          style: PaycheckType.bodyStrong(),
        ),
        subtitle: Text(
          '${document.documentType} · ${document.parseStatusLabel}',
          style: PaycheckType.utility(),
        ),
      ),
    );
  }
}

class _EmptyEvidence extends StatelessWidget {
  const _EmptyEvidence({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: PaycheckColors.contractSoft,
        borderRadius: AppRadius.card,
      ),
      child: Row(
        children: [
          const Icon(Icons.add_to_drive_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Add an offer letter, payslip, bill, or receipt first.',
              style: PaycheckType.body(),
            ),
          ),
          TextButton(onPressed: onAdd, child: const Text('Add')),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: PaycheckType.body(),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

String _money(int amount) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(amount);
