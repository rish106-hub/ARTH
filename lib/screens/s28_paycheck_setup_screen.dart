import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/paycheck_provider.dart';
import '../providers/tax_document_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/on_device_document_ocr_service.dart';
import '../theme/paycheck_theme.dart';
import '../widgets/arth_brand_mark.dart';
import '../widgets/job_duration_selector.dart';

class PaycheckSetupScreen extends ConsumerStatefulWidget {
  const PaycheckSetupScreen({super.key});

  @override
  ConsumerState<PaycheckSetupScreen> createState() =>
      _PaycheckSetupScreenState();
}

class _PaycheckSetupScreenState extends ConsumerState<PaycheckSetupScreen> {
  bool _openingFile = false;

  Future<void> _chooseDocument({
    required String documentType,
    required String pickerLabel,
  }) async {
    setState(() => _openingFile = true);
    try {
      const typeGroup = XTypeGroup(
        label: 'Pay document',
        extensions: ['pdf', 'png', 'jpg', 'jpeg'],
      );
      final file = await openFile(acceptedTypeGroups: const [typeGroup]);
      if (file == null || !mounted) return;
      final extension = file.name.split('.').last.toLowerCase();
      final mimeType = switch (extension) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        _ => 'application/octet-stream',
      };
      final rawBytes = await file.readAsBytes();
      if (rawBytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That file looks empty. Try another.')),
        );
        return;
      }

      // Downscale/compress images before upload so a large phone photo doesn't
      // exceed the server upload limit ("body too large"). PDFs pass through.
      List<int> uploadBytes = rawBytes;
      var uploadFilename = file.name;
      var uploadMimeType = mimeType;
      String? ocrText;
      if (mimeType.startsWith('image/')) {
        final ocr = OnDeviceDocumentOcrService();
        try {
          final prepared = await ocr.prepareForUploadAsync(
            bytes: rawBytes,
            filename: file.name,
          );
          uploadBytes = prepared.bytes;
          uploadFilename = prepared.filename;
          uploadMimeType = prepared.mimeType;
          ocrText = await ocr.extractLatinTextFromPreparedImage(prepared);
        } catch (_) {
          // Fall back to the raw image; upload still allows manual review.
        }
      }
      if (!mounted) return;
      if (uploadBytes.length > 10 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That file is too large (max 10 MB). Try a photo or a smaller PDF.',
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      await ref.read(taxDocumentProvider.notifier).upload(
            documentType: documentType,
            filename: uploadFilename,
            mimeType: uploadMimeType,
            bytes: uploadBytes,
            ocrText: ocrText,
          );
      if (!mounted) return;
      if (documentType == 'offerLetter') {
        ref.read(paycheckProvider.notifier).markOfferLetterAdded();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$pickerLabel added. Check the details next.')),
      );
      context.go('/paycheck/evidence');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _openingFile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ArthBrandMark(
                    size: 30,
                    spacing: 9,
                    wordmarkStyle: PaycheckType.heading(),
                  ),
                  const Spacer(),
                  Text('Private by default', style: PaycheckType.utility()),
                ],
              ),
              const SizedBox(height: 52),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: PaycheckColors.contract,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Start with what you were promised',
                style: PaycheckType.title().copyWith(fontSize: 30),
              ),
              const SizedBox(height: 14),
              Text(
                'Add an offer letter. ARTH turns each pay component into a monthly checklist, then matches it against payslips and salary alerts.',
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
              const SizedBox(height: 30),
              Text('How long does this job run?',
                  style: PaycheckType.bodyStrong()),
              const SizedBox(height: 6),
              Text(
                'Not every job lasts the full year. We annualize your salary over these months for accurate tax.',
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
              const SizedBox(height: 12),
              JobDurationSelector(
                selectedMonths: ref.watch(
                  userProfileProvider
                      .select((profile) => profile.jobDurationMonths),
                ),
                onChanged: (months) => ref
                    .read(userProfileProvider.notifier)
                    .updateField((profile) =>
                        profile.copyWith(jobDurationMonths: months)),
              ),
              const SizedBox(height: 34),
              const _SetupStep(
                number: '01',
                title: 'Add your offer letter',
                detail: 'PDF or image. You review every extracted number.',
                stateLabel: 'Start here',
                active: true,
              ),
              const _SetupConnector(),
              const _SetupStep(
                number: '02',
                title: 'Connect salary emails',
                detail:
                    'Later, use narrow read-only access for payslips and bills.',
                stateLabel: 'Optional',
              ),
              const _SetupConnector(),
              const _SetupStep(
                number: '03',
                title: 'Review your first match',
                detail: 'See promised, received and still claimable money.',
                stateLabel: 'About 2 min',
              ),
              const SizedBox(height: 34),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: PaycheckColors.ink,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _openingFile
                      ? null
                      : () => _chooseDocument(
                            documentType: 'offerLetter',
                            pickerLabel: 'Offer letter',
                          ),
                  child: Text(
                    _openingFile ? 'Opening files…' : 'Add offer letter',
                    style: PaycheckType.bodyStrong(color: Colors.white),
                  ),
                ),
              ),
              TextButton(
                onPressed: _openingFile
                    ? null
                    : () => _chooseDocument(
                          documentType: 'payslip',
                          pickerLabel: 'Payslip',
                        ),
                child: const Text('I only have a payslip'),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'No bank login. No payment access.',
                  style: PaycheckType.utility(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  final String number;
  final String title;
  final String detail;
  final String stateLabel;
  final bool active;

  const _SetupStep({
    required this.number,
    required this.title,
    required this.detail,
    required this.stateLabel,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? PaycheckColors.contract : PaycheckColors.paper,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? PaycheckColors.contract : PaycheckColors.line,
            ),
          ),
          child: Text(
            number,
            style: PaycheckType.utility(
              color: active ? Colors.white : PaycheckColors.inkSoft,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text(title, style: PaycheckType.bodyStrong())),
                  Text(stateLabel, style: PaycheckType.utility()),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                detail,
                style: PaycheckType.body(color: PaycheckColors.inkSoft),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SetupConnector extends StatelessWidget {
  const _SetupConnector();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.only(left: 19),
      color: PaycheckColors.line,
    );
  }
}
