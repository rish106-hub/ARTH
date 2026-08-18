import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../models/tax_document.dart';
import '../../../providers/tax_document_provider.dart';
import '../../../providers/tax_year_provider.dart';
import '../../../theme/paycheck_theme.dart';
import '../../../widgets/premium_ui.dart';
import '../engine/offer_take_home_engine.dart';
import '../models/offer_comparison_models.dart';
import '../providers/offer_comparison_provider.dart';

String _money(int amount) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(amount);

/// Compares job offers the candidate has already uploaded, then asks at most five
/// questions and shows a verdict plus a negotiation play.
///
/// One screen for three stages, because it is one decision made in one sitting.
class OfferCompareScreen extends ConsumerWidget {
  const OfferCompareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(offerCompareProvider);

    return Scaffold(
      backgroundColor: PaycheckColors.canvas,
      appBar: AppBar(
        backgroundColor: PaycheckColors.canvas,
        foregroundColor: PaycheckColors.ink,
        elevation: 0,
        title: const Text('Compare offers'),
        leading: state.stage == OfferCompareStage.pickingOffers
            ? null
            : IconButton(
                key: const Key('offer_compare_restart'),
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    ref.read(offerCompareProvider.notifier).reset(),
              ),
      ),
      body: SafeArea(
        child: switch (state.stage) {
          OfferCompareStage.pickingOffers => const _OfferPicker(),
          OfferCompareStage.answering => const _QuestionsView(),
          OfferCompareStage.reading => const _VerdictView(),
        },
      ),
    );
  }
}

class _OfferPicker extends ConsumerWidget {
  const _OfferPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(taxDocumentProvider);
    final state = ref.watch(offerCompareProvider);
    final notifier = ref.read(offerCompareProvider.notifier);

    return documents.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message(
        title: 'Could not load your documents',
        body: error.toString(),
      ),
      data: (all) {
        final offers = all
            .where((document) => document.documentType == 'offerLetter')
            .toList(growable: false);
        if (offers.isEmpty) {
          return const _Message(
            title: 'No offer letters yet',
            body: 'Upload them from your document vault, then come back.',
          );
        }

        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                'Pick the offers to compare. The order you pick them is the '
                'order they appear in.',
                style: TextStyle(color: PaycheckColors.inkSoft, height: 1.4),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: offers.length,
                itemBuilder: (context, index) {
                  final document = offers[index];
                  final rank = state.selectedDocumentIds.indexOf(document.id);
                  return _OfferPickerTile(
                    document: document,
                    pickOrder: rank == -1 ? null : rank + 1,
                    onTap: () => notifier.toggleOffer(document.id),
                  );
                },
              ),
            ),
            if (state.errorMessage != null)
              _ErrorBanner(message: state.errorMessage!),
            _PrimaryAction(
              key: const Key('offer_compare_start'),
              label: state.selectedDocumentIds.length < 2
                  ? 'Compare'
                  : 'Compare ${state.selectedDocumentIds.length} offers',
              isBusy: state.isBusy,
              onPressed:
                  state.selectedDocumentIds.isEmpty ? null : notifier.start,
            ),
          ],
        );
      },
    );
  }
}

class _OfferPickerTile extends StatelessWidget {
  const _OfferPickerTile({
    required this.document,
    required this.pickOrder,
    required this.onTap,
  });

  final TaxDocument document;
  final int? pickOrder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = pickOrder != null;
    return Card(
      color: selected ? PaycheckColors.contractSoft : PaycheckColors.paper,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? PaycheckColors.contract : PaycheckColors.border,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(
          document.userLabel?.trim().isNotEmpty == true
              ? document.userLabel!.trim()
              : document.originalFilename,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          // An offer letter that was never interpreted cannot be compared, and
          // saying so here is kinder than a failure after the tap.
          document.parseStatus == 'metadata_ready'
              ? 'Not read yet — open it and confirm the details first'
              : 'Ready to compare',
          style: const TextStyle(color: PaycheckColors.inkSoft),
        ),
        trailing: selected
            ? CircleAvatar(
                radius: 14,
                backgroundColor: PaycheckColors.contract,
                child: Text(
                  '$pickOrder',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              )
            : const Icon(Icons.circle_outlined, color: PaycheckColors.inkMuted),
      ),
    );
  }
}

class _QuestionsView extends ConsumerWidget {
  const _QuestionsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(offerCompareProvider);
    final notifier = ref.read(offerCompareProvider.notifier);
    final comparison = state.comparison!;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            children: [
              _ComparisonSummary(comparison: comparison),
              const SizedBox(height: 8),
              Text(
                comparison.questions.length == 1
                    ? 'One question before the verdict.'
                    : '${comparison.questions.length} questions before the '
                        'verdict. Each one can change the answer.',
                style: const TextStyle(
                  color: PaycheckColors.inkSoft,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              for (final question in comparison.questions)
                _QuestionCard(
                  question: question,
                  answer: state.draftAnswers[question.id],
                  onAnswer: (value) => notifier.answer(question.id, value),
                ),
            ],
          ),
        ),
        if (state.adviceUnavailable)
          const _ErrorBanner(
            message: 'Answers saved. The verdict could not be generated — '
                'try again in a moment.',
          ),
        if (state.errorMessage != null)
          _ErrorBanner(message: state.errorMessage!),
        _PrimaryAction(
          key: const Key('offer_compare_submit'),
          label: 'Show the verdict',
          isBusy: state.isBusy,
          onPressed: state.canSubmitAnswers ? notifier.submitAnswers : null,
        ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.answer,
    required this.onAnswer,
  });

  final OfferQuestion question;
  final String? answer;
  final ValueChanged<String> onAnswer;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: PaycheckColors.paper,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: PaycheckColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question.prompt,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            if (question.isFreeText)
              TextField(
                key: Key('offer_answer_${question.id}'),
                minLines: 2,
                maxLines: 4,
                maxLength: 600,
                onChanged: onAnswer,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Your answer',
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in question.options)
                    ChoiceChip(
                      key: Key('offer_answer_${question.id}_${option.value}'),
                      label: Text(option.label),
                      selected: answer == option.value,
                      onSelected: (_) => onAnswer(option.value),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _VerdictView extends ConsumerWidget {
  const _VerdictView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comparison = ref.watch(offerCompareProvider).comparison!;
    final advice = comparison.advice!;
    final target = comparison.offerById(advice.negotiation.targetDocumentId);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          color: PaycheckColors.contractSoft,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: PaycheckColors.contract),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  advice.verdict.headline,
                  key: const Key('offer_verdict_headline'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                Text(advice.verdict.reasoning,
                    style: const TextStyle(height: 1.45)),
                const SizedBox(height: 12),
                // The caveat sits inside the verdict card on purpose. What this
                // cannot know belongs next to what it claims, not further down
                // the page where it reads as small print.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 18, color: PaycheckColors.inkSoft),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        advice.verdict.caveat,
                        style: const TextStyle(
                          color: PaycheckColors.inkSoft,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _ComparisonSummary(comparison: comparison),
        const SizedBox(height: 16),
        const _SectionTitle('How to negotiate'),
        Card(
          color: PaycheckColors.paper,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: PaycheckColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${target?.displayName ?? 'This offer'} · '
                  '${advice.negotiation.componentLabel}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(advice.negotiation.ask,
                    style: const TextStyle(height: 1.45)),
                const SizedBox(height: 16),
                for (final line in advice.negotiation.script)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child:
                        Text('“$line”', style: const TextStyle(height: 1.45)),
                  ),
                const Divider(height: 24),
                Text(
                  advice.negotiation.walkAway,
                  style: const TextStyle(
                    color: PaycheckColors.inkSoft,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The pay decomposition, plus the take-home estimate the app adds on top.
class _ComparisonSummary extends ConsumerWidget {
  const _ComparisonSummary({required this.comparison});

  final OfferComparison comparison;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ruleSet = ref.watch(activeTaxRuleSetProvider);
    final takeHome = ruleSet.asData == null
        ? const <String, int>{}
        : OfferTakeHomeEngine.monthlyTakeHomeByOffer(
            comparison,
            ruleSet: ruleSet.asData!.value,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (comparison.largestCtcIsNotBestGuaranteed)
          Container(
            key: const Key('offer_ctc_warning'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PaycheckColors.claimSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'The biggest CTC here is not the best offer on pay you can count '
              'on every month.',
              style: TextStyle(height: 1.4, fontWeight: FontWeight.w600),
            ),
          ),
        if (comparison.currencies.length > 1)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PaycheckColors.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'These offers are in different currencies, so ARTH will not rank '
              'them on money.',
              style: TextStyle(height: 1.4),
            ),
          ),
        for (final offer in comparison.offers)
          _OfferSummaryCard(
            offer: offer,
            isWinner: comparison.rankedDocumentIds.isNotEmpty &&
                comparison.rankedDocumentIds.first == offer.documentId,
            monthlyTakeHome: takeHome[offer.documentId],
          ),
        if (takeHome.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ArthDisclosure(
              label: OfferTakeHomeEngine.assumptionLabel,
              detail: OfferTakeHomeEngine.assumptionLines.join(' '),
            ),
          ),
      ],
    );
  }
}

class _OfferSummaryCard extends StatelessWidget {
  const _OfferSummaryCard({
    required this.offer,
    required this.isWinner,
    required this.monthlyTakeHome,
  });

  final NormalizedOffer offer;
  final bool isWinner;
  final int? monthlyTakeHome;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: PaycheckColors.paper,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isWinner ? PaycheckColors.matched : PaycheckColors.border,
          width: isWinner ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    offer.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (isWinner)
                  const Text(
                    'Best on guaranteed pay',
                    style: TextStyle(
                      color: PaycheckColors.matched,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            if (offer.roleTitle?.trim().isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  offer.roleTitle!.trim(),
                  style: const TextStyle(color: PaycheckColors.inkSoft),
                ),
              ),
            const SizedBox(height: 12),
            _Row(
              label: 'Guaranteed a year',
              value: offer.guaranteedAnnualPay == null
                  // Not "₹0": the letter did not say, which is a different fact.
                  ? 'Not stated'
                  : _money(offer.guaranteedAnnualPay!),
              emphasise: true,
            ),
            _Row(
              label: 'At risk a year',
              value: offer.atRiskShareBasisPoints == null
                  ? _money(offer.atRiskAnnualPay)
                  : '${_money(offer.atRiskAnnualPay)} · '
                      '${(offer.atRiskShareBasisPoints! / 100).toStringAsFixed(0)}%',
            ),
            if (offer.oneTimePay > 0)
              _Row(label: 'Paid once', value: _money(offer.oneTimePay)),
            if (offer.annualCtc != null)
              _Row(label: 'Stated CTC', value: _money(offer.annualCtc!)),
            if (monthlyTakeHome != null)
              _Row(
                label: 'Take-home a month',
                value: _money(monthlyTakeHome!),
              ),
            for (final unknown in offer.unknowns)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${unknown.label} — ${unknown.reason.label.toLowerCase()}',
                  style: const TextStyle(
                    color: PaycheckColors.inkMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            for (final warning in offer.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  warning,
                  style: const TextStyle(
                    color: PaycheckColors.claim,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: PaycheckColors.inkSoft)),
          Text(
            value,
            style: TextStyle(
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: PaycheckColors.inkSoft,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PaycheckColors.claimSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: const TextStyle(height: 1.4)),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    super.key,
    required this.label,
    required this.isBusy,
    required this.onPressed,
  });

  final String label;
  final bool isBusy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: isBusy ? null : onPressed,
          child: isBusy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(label),
        ),
      ),
    );
  }
}
