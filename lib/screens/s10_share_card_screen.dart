import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:screenshot/screenshot.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../providers/tax_result_provider.dart';
// user_profile_provider not needed here;
import '../widgets/animated_number.dart';
import '../widgets/question_progress_bar.dart';
import '../widgets/premium_ui.dart';
import '../widgets/retry_error_state.dart';

class ShareCardScreen extends ConsumerStatefulWidget {
  const ShareCardScreen({super.key});

  @override
  ConsumerState<ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends ConsumerState<ShareCardScreen> {
  final _screenshotCtrl = ScreenshotController();
  bool _sharing = false;

  Future<void> _share(int totalGap, List<_ShareItem> items) async {
    if (_sharing) return;
    setState(() => _sharing = true);

    try {
      final image = await _screenshotCtrl.capture(pixelRatio: 3.0);
      if (image == null) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(image, mimeType: 'image/png', name: 'arth_gap.png'),
          ],
          text: 'I found ₹${_fmt(totalGap)} in deduction opportunities '
              'with ARTH.\n\nhttps://arth-website.vercel.app/',
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _fmt(int v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).round()}K';
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final resultAsync = ref.watch(taxResultProvider);

    return Scaffold(
      backgroundColor: PaycheckColors.bgPrimary,
      appBar: const ArthAppBar(title: 'Share Opportunity'),
      body: resultAsync.when(
        loading: () => const ArthLoadingPanel(
          title: 'Preparing your share card',
          insights: [
            'Removing private profile details.',
            'Keeping only sections and amounts.',
            'Building a clean summary card.',
          ],
        ),
        error: (_, __) => RetryErrorState(
          message: 'Could not prepare your share card',
          onRetry: () => ref.invalidate(taxResultProvider),
        ),
        data: (result) {
          final gaps = result.gaps.take(5).toList();
          final items = gaps
              .map((g) => _ShareItem(section: g.section, amount: g.gapAmount))
              .toList();
          final total = result.totalGapAmount;

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        'Your shareable card',
                        style: PaycheckType.caption(
                          color: PaycheckColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // The card itself (screenshot target)
                      Screenshot(
                        controller: _screenshotCtrl,
                        child: _ShareCard(
                          totalGap: total,
                          items: items,
                          ruleLabel: result.ruleSetLabel,
                        ),
                      ),

                      const SizedBox(height: 20),

                      Text(
                        'No PAN, no salary — section names and amounts only.',
                        style: PaycheckType.micro(
                          color: PaycheckColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              // Share button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: AppButtons.primaryGold,
                    onPressed: _sharing ? null : () => _share(total, items),
                    icon: _sharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: PaycheckColors.bgPrimary,
                            ),
                          )
                        : const Icon(Icons.ios_share_rounded, size: 18),
                    label:
                        Text(_sharing ? 'Preparing...' : 'Share Opportunity'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ShareItem {
  final String section;
  final int amount;
  const _ShareItem({required this.section, required this.amount});
}

class _ShareCard extends StatelessWidget {
  final int totalGap;
  final List<_ShareItem> items;
  final String ruleLabel;

  const _ShareCard({
    required this.totalGap,
    required this.items,
    required this.ruleLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: PaycheckColors.bgPrimary,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: PaycheckColors.gold.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: PaycheckColors.divider)),
            ),
            child: Row(
              children: [
                Text(
                  'ARTH',
                  style: PaycheckType.heading(
                    color: PaycheckColors.gold,
                  ).copyWith(fontSize: 20, letterSpacing: 0),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tax Readiness Cockpit',
                    style:
                        PaycheckType.micro(color: PaycheckColors.textSecondary),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Main gap
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deduction opportunities',
                  style: PaycheckType.body(color: PaycheckColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹ ${_fmtFull(totalGap)}',
                  style: PaycheckType.display(
                    color: PaycheckColors.gold,
                  ).copyWith(fontSize: 48, height: 1),
                ),
                const SizedBox(height: 4),
                Text(
                  ruleLabel,
                  style: PaycheckType.body(color: PaycheckColors.textPrimary),
                ),
              ],
            ),
          ),

          // Divider
          Container(height: 1, color: PaycheckColors.divider),

          // Section breakdown
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              children: items.map((item) => _ShareItemRow(item: item)).toList(),
            ),
          ),

          // Footer
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: PaycheckColors.bgCard,
                borderRadius: AppRadius.card,
                border: Border.all(
                  color: PaycheckColors.gold.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Build yours →',
                    style: PaycheckType.bodyMedium(color: PaycheckColors.gold),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'arth-website.vercel.app',
                    style: PaycheckType.caption(
                      color: PaycheckColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtFull(int v) {
    if (v >= 100000) {
      final l = v / 100000;
      return '${l.toStringAsFixed(l == l.roundToDouble() ? 0 : 1)} Lakh';
    }
    return v.toString().replaceAllMapped(
          RegExp(r'(\d{1,2})(?=(\d{2})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }
}

class _ShareItemRow extends StatelessWidget {
  final _ShareItem item;
  const _ShareItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 360;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: PaycheckColors.gold.withValues(alpha: 0.1),
                      borderRadius: AppRadius.pill,
                      border: Border.all(
                        color: PaycheckColors.gold.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      item.section,
                      style: PaycheckType.sectionLabel(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  compact
                      ? '₹ ${formatRupeesCompact(item.amount)}'
                      : '₹ ${_fmtFull(item.amount)}',
                  style: PaycheckType.bodyMedium(
                      color: PaycheckColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtFull(int v) {
    if (v >= 100000) {
      final l = v / 100000;
      return '${l.toStringAsFixed(l == l.roundToDouble() ? 0 : 1)} Lakh';
    }
    return v.toString().replaceAllMapped(
          RegExp(r'(\d{1,2})(?=(\d{2})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }
}
