import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';

class TaxJourneyScene extends StatefulWidget {
  final int step;
  final UserProfile profile;
  final String chapter;
  final String helper;
  final Color accent;
  final double height;

  const TaxJourneyScene({
    super.key,
    required this.step,
    required this.profile,
    required this.chapter,
    required this.helper,
    required this.accent,
    this.height = 218,
  });

  @override
  State<TaxJourneyScene> createState() => _TaxJourneySceneState();
}

class _TaxJourneySceneState extends State<TaxJourneyScene>
    with SingleTickerProviderStateMixin {
  bool _showWhy = false;
  late final AnimationController _pulseController;
  late final Animation<double> _sceneMotion;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
      lowerBound: 0,
      upperBound: 1,
    )..repeat(reverse: true);
    _sceneMotion = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOutSine,
      reverseCurve: Curves.easeInOutSine,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TaxJourneyScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step != widget.step) _showWhy = false;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _JourneySnapshot.forStep(widget.step, widget.profile);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pulse =
        reduceMotion ? const AlwaysStoppedAnimation(0.5) : _sceneMotion;

    return Semantics(
      button: true,
      label:
          _showWhy ? 'Close why this matters' : 'Open why this answer matters',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.card,
          onTap: () => setState(() => _showWhy = !_showWhy),
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : AppMotion.medium,
            height: widget.height,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F0E8),
              borderRadius: AppRadius.card,
              border: Border.all(
                color: _showWhy
                    ? widget.accent.withValues(alpha: 0.55)
                    : PaycheckColors.border,
              ),
              boxShadow: [
                BoxShadow(
                  color: PaycheckColors.textPrimary.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: _QuestionArtwork(
                    key: ValueKey(widget.step),
                    step: widget.step,
                    city: widget.profile.city,
                    animation: pulse,
                    accent: widget.accent,
                  ),
                ),
                if (!_showWhy) ...[
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _ChapterPill(
                      label: widget.chapter,
                      accent: widget.accent,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _SnapshotStrip(
                      snapshot: snapshot,
                      accent: widget.accent,
                    ),
                  ),
                ],
                AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : AppMotion.medium,
                  child: _showWhy
                      ? _WhyOverlay(
                          key: ValueKey('why-${widget.step}'),
                          chapter: widget.chapter,
                          helper: widget.helper,
                          accent: widget.accent,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChapterPill extends StatelessWidget {
  final String label;
  final Color accent;

  const _ChapterPill({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: AppRadius.pill,
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Text(
        label.toUpperCase(),
        style: PaycheckType.micro(color: PaycheckColors.textPrimary).copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _QuestionArtwork extends StatelessWidget {
  final int step;
  final String city;
  final Color accent;
  final Animation<double> animation;

  const _QuestionArtwork({
    super.key,
    required this.step,
    required this.city,
    required this.accent,
    required this.animation,
  });

  static const _backgrounds = <Color>[
    Color(0xFFFFE9A8),
    Color(0xFFD9E8FF),
    Color(0xFFD7F2E8),
    Color(0xFFFFDDD2),
    Color(0xFFE5E0FF),
    Color(0xFFFFE2A9),
    Color(0xFFD6EFE4),
    Color(0xFFE2E5FF),
    Color(0xFFD6EFF5),
    Color(0xFFFFE0E7),
    Color(0xFFFFE8C7),
    Color(0xFFDDE9F3),
  ];

  @override
  Widget build(BuildContext context) {
    final normalizedCity = city.trim().toLowerCase();
    if (step == 2 &&
        (normalizedCity == 'delhi' || normalizedCity == 'new delhi')) {
      return Image.asset(
        'assets/images/india-heritage-landmark.jpg',
        fit: BoxFit.cover,
        alignment: Alignment.center,
        semanticLabel: 'Red Fort, Delhi',
      );
    }
    final index = step.clamp(0, _backgrounds.length - 1);
    return AnimatedContainer(
      duration: AppMotion.medium,
      color: _backgrounds[index],
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) => CustomPaint(
          isComplex: true,
          willChange: true,
          painter: _QuestionScenePainter(
            step: step,
            progress: animation.value,
            accent: accent,
          ),
        ),
      ),
    );
  }
}

class _QuestionScenePainter extends CustomPainter {
  final int step;
  final double progress;
  final Color accent;

  const _QuestionScenePainter({
    required this.step,
    required this.progress,
    required this.accent,
  });

  static const _ink = Color(0xFF102C25);
  static const _paper = Color(0xFFFFFCF5);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height - 62;
    switch (step) {
      case 0:
        _income(canvas, size.width, h);
      case 1:
        _employment(canvas, size.width, h);
      case 2:
        _city(canvas, size.width, h);
      case 3:
        _rent(canvas, size.width, h);
      case 4:
        _hra(canvas, size.width, h);
      case 5:
        _investments(canvas, size.width, h);
      case 6:
        _homeLoan(canvas, size.width, h);
      case 7:
        _nps(canvas, size.width, h);
      case 8:
        _health(canvas, size.width, h);
      case 9:
        _education(canvas, size.width, h);
      case 10:
        _donations(canvas, size.width, h);
      default:
        _age(canvas, size.width, h);
    }
  }

  void _income(Canvas c, double w, double h) {
    _card(c, Rect.fromLTWH(w * .34, 22, w * .34, h - 32), -0.06);
    _text(c, 'PAYSLIP', Offset(w * .39, 39), 13, _ink, bold: true);
    for (var i = 0; i < 3; i++) {
      _line(c, Offset(w * .39, 66 + i * 15),
          Offset(w * (.55 + i * .02), 66 + i * 15));
    }
    final coinY = 34 + progress * 12;
    for (var i = 0; i < 3; i++) {
      _coin(c, Offset(w * .76 + i * 24, coinY + i * 27),
          i == 1 ? accent : _paper);
    }
    for (var i = 0; i < 4; i++) {
      _rect(
          c,
          Rect.fromLTWH(34 + i * 25, h - 28 - i * 13 * progress, 16,
              18 + i * 13 * progress),
          _ink,
          radius: 5);
    }
  }

  void _employment(Canvas c, double w, double h) {
    final lift = progress * 7;
    _card(c, Rect.fromLTWH(w * .38, 25 - lift, w * .28, h - 38), -0.08);
    _circle(c, Offset(w * .47, 58 - lift), 18, accent);
    _line(c, Offset(w * .42, 91 - lift), Offset(w * .59, 91 - lift), width: 7);
    _line(c, Offset(w * .44, 108 - lift), Offset(w * .57, 108 - lift),
        color: Colors.black26, width: 5);
    _rect(c, Rect.fromLTWH(w * .72, 46 + lift, 74, 58), _ink, radius: 8);
    _rect(c, Rect.fromLTWH(w * .75, 37 + lift, 28, 14), _paper, radius: 5);
    _text(c, 'WORK', Offset(w * .75, 67 + lift), 12, Colors.white, bold: true);
  }

  void _city(Canvas c, double w, double h) {
    for (var i = 0; i < 7; i++) {
      final height = 35.0 + (i % 3) * 23;
      _rect(
          c,
          Rect.fromLTWH(
              22 + i * (w - 44) / 7, h - height, (w - 70) / 7, height),
          i.isEven ? _ink : Colors.white70,
          radius: 4);
    }
    final trainX = 22 + (w - 105) * progress;
    _line(c, Offset(18, h - 4), Offset(w - 18, h - 4), width: 4);
    _rect(c, Rect.fromLTWH(trainX, h - 28, 72, 24), accent, radius: 8);
    _circle(c, Offset(w * .72, 45), 18 + progress * 7,
        accent.withValues(alpha: .25));
    _circle(c, Offset(w * .72, 45), 11, accent);
  }

  void _rent(Canvas c, double w, double h) {
    final house = Path()
      ..moveTo(w * .38, h * .48)
      ..lineTo(w * .55, 24)
      ..lineTo(w * .72, h * .48)
      ..lineTo(w * .68, h - 8)
      ..lineTo(w * .42, h - 8)
      ..close();
    c.drawPath(house, Paint()..color = _paper);
    c.drawPath(
        house,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
    _rect(c, Rect.fromLTWH(w * .52, h - 54, 36, 46), accent, radius: 4);
    c.save();
    c.translate(w * .79, 38);
    c.rotate(-.18 + progress * .36);
    _circle(c, Offset.zero, 15, _ink);
    _line(c, const Offset(0, 15), const Offset(0, 66), width: 9);
    _line(c, const Offset(0, 58), const Offset(20, 58), width: 8);
    c.restore();
  }

  void _hra(Canvas c, double w, double h) {
    _card(c, Rect.fromLTWH(w * .32, 16, w * .42, h - 22), 0.04);
    _text(c, 'SALARY', Offset(w * .38, 34), 12, _ink, bold: true);
    for (var i = 0; i < 4; i++) {
      final y = 58.0 + i * 18;
      _line(c, Offset(w * .37, y), Offset(w * .66, y),
          color: i == 2 ? accent : Colors.black26, width: i == 2 ? 10 : 6);
    }
    _text(c, 'HRA', Offset(w * .48, 91), 11, Colors.white, bold: true);
    final lens = Offset(w * .76 + progress * 8, 82 - progress * 5);
    c.drawCircle(lens, 30, Paint()..color = Colors.white54);
    c.drawCircle(
        lens,
        30,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5);
    _line(c, lens + const Offset(21, 21), lens + const Offset(49, 49),
        width: 9);
  }

  void _investments(Canvas c, double w, double h) {
    _rect(c, Rect.fromLTWH(w * .36, 29, w * .32, h - 38), _ink, radius: 14);
    _text(c, '80C', Offset(w * .45, 60), 28, Colors.white, bold: true);
    _rect(c, Rect.fromLTWH(w * .42, 95, w * .2 * progress, 12), accent,
        radius: 6);
    for (var i = 0; i < 3; i++) {
      _coin(c, Offset(w * .75 + i * 25, 44 + i * 28 - progress * 7),
          i == 1 ? accent : _paper);
    }
  }

  void _homeLoan(Canvas c, double w, double h) {
    final roof = Path()
      ..moveTo(w * .3, 78)
      ..lineTo(w * .49, 22)
      ..lineTo(w * .68, 78)
      ..close();
    c.drawPath(roof, Paint()..color = accent);
    _rect(c, Rect.fromLTWH(w * .34, 72, w * .3, h - 78), _paper, radius: 4);
    _rect(c, Rect.fromLTWH(w * .46, h - 53, 34, 45), _ink, radius: 3);
    final slide = progress * 10;
    _card(c, Rect.fromLTWH(w * .7 + slide, 29, 84, 91), 0.06);
    _text(c, 'EMI', Offset(w * .75 + slide, 49), 13, _ink, bold: true);
    _text(c, '%', Offset(w * .77 + slide, 78), 28, accent, bold: true);
  }

  void _nps(Canvas c, double w, double h) {
    _rect(c, Rect.fromLTWH(w * .4, 39, w * .27, h - 44), Colors.white70,
        radius: 18);
    _line(c, Offset(w * .43, 39), Offset(w * .64, 39), width: 9);
    _text(c, 'NPS', Offset(w * .47, h - 41), 18, _ink, bold: true);
    for (var i = 0; i < 4; i++) {
      final y = 20.0 + i * 25 + progress * 17;
      _coin(c, Offset(w * .54 + (i.isEven ? -18 : 18), y),
          i == 2 ? accent : _paper,
          radius: 15);
    }
    _text(c, '60', Offset(w * .76, 48), 30, _ink, bold: true);
    _text(c, 'years', Offset(w * .76, 80), 12, _ink);
  }

  void _health(Canvas c, double w, double h) {
    final center = Offset(w * .54, h * .54);
    final shield = Path()
      ..moveTo(center.dx, 19)
      ..lineTo(center.dx + 68, 43)
      ..lineTo(center.dx + 52, h - 22)
      ..lineTo(center.dx, h - 4)
      ..lineTo(center.dx - 52, h - 22)
      ..lineTo(center.dx - 68, 43)
      ..close();
    c.drawPath(shield, Paint()..color = _paper);
    c.drawPath(
        shield,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
    _line(c, center + const Offset(-22, -4), center + const Offset(22, -4),
        color: accent, width: 13);
    _line(c, center + const Offset(0, -26), center + const Offset(0, 18),
        color: accent, width: 13);
    final beat = 8 + progress * 10;
    _line(c, Offset(20, h - 20), Offset(w * .25, h - 20), width: 4);
    _line(c, Offset(w * .25, h - 20), Offset(w * .3, h - 20 - beat),
        color: accent, width: 4);
    _line(c, Offset(w * .3, h - 20 - beat), Offset(w * .35, h - 10),
        color: accent, width: 4);
  }

  void _education(Canvas c, double w, double h) {
    for (var i = 0; i < 3; i++) {
      _rect(c, Rect.fromLTWH(w * .34 + i * 9, h - 35 - i * 25, w * .3, 22),
          i == 1 ? accent : _ink,
          radius: 5);
    }
    final bob = progress * 8;
    final cap = Path()
      ..moveTo(w * .52, 23 - bob)
      ..lineTo(w * .69, 49 - bob)
      ..lineTo(w * .52, 75 - bob)
      ..lineTo(w * .35, 49 - bob)
      ..close();
    c.drawPath(cap, Paint()..color = _ink);
    _line(c, Offset(w * .66, 52 - bob), Offset(w * .72, 94 - bob),
        color: accent, width: 4);
    _text(c, '%', Offset(w * .77, 63), 34, accent, bold: true);
  }

  void _donations(Canvas c, double w, double h) {
    final scale = 1 + progress * .1;
    c.save();
    c.translate(w * .53, 66);
    c.scale(scale);
    final heart = Path()
      ..moveTo(0, 34)
      ..cubicTo(-62, 0, -42, -43, 0, -18)
      ..cubicTo(42, -43, 62, 0, 0, 34)
      ..close();
    c.drawPath(heart, Paint()..color = accent);
    c.restore();
    _card(c, Rect.fromLTWH(w * .72, 33, 78, 92), 0.08);
    _text(c, '80G', Offset(w * .75, 55), 15, _ink, bold: true);
    _line(c, Offset(w * .75, 83), Offset(w * .85, 83),
        color: Colors.black26, width: 5);
    _circle(c, Offset(w * .82, 109), 10 + progress * 3, _ink);
  }

  void _age(Canvas c, double w, double h) {
    _line(c, Offset(w * .24, h * .62), Offset(w * .83, h * .62), width: 6);
    for (var i = 0; i < 4; i++) {
      final active = progress * 3 >= i;
      _circle(c, Offset(w * (.25 + i * .19), h * .62), active ? 15 : 10,
          active ? accent : _paper);
      _text(c, '${20 + i * 15}', Offset(w * (.23 + i * .19), h * .82), 11, _ink,
          bold: true);
    }
    _circle(c, Offset(w * .54, 42), 28, _paper);
    _circle(c, Offset(w * .54, 36), 11, _ink);
    _rect(c, Rect.fromLTWH(w * .49, 49, w * .1, 32), _ink, radius: 16);
  }

  void _card(Canvas c, Rect rect, double angle) {
    c.save();
    c.translate(rect.center.dx, rect.center.dy);
    c.rotate(angle);
    final local = Rect.fromCenter(
        center: Offset.zero, width: rect.width, height: rect.height);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(local, const Radius.circular(10)));
    c.drawShadow(path, Colors.black26, 8, false);
    c.drawPath(path, Paint()..color = _paper);
    c.drawPath(
        path,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    c.restore();
  }

  void _coin(Canvas c, Offset center, Color color, {double radius = 18}) {
    _circle(c, center, radius, color);
    c.drawCircle(
        center,
        radius,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    _text(c, '₹', center - Offset(radius * .38, radius * .63), radius * 1.05,
        _ink,
        bold: true);
  }

  void _circle(Canvas c, Offset center, double radius, Color color) {
    c.drawCircle(center, radius, Paint()..color = color);
  }

  void _rect(Canvas c, Rect rect, Color color, {double radius = 0}) {
    c.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        Paint()..color = color);
  }

  void _line(Canvas c, Offset from, Offset to,
      {Color color = _ink, double width = 3}) {
    c.drawLine(
        from,
        to,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round);
  }

  void _text(Canvas c, String value, Offset offset, double size, Color color,
      {bool bold = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: PaycheckType.bodyMedium(
          color: color,
        ).copyWith(
          fontSize: size,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(c, offset);
  }

  @override
  bool shouldRepaint(_QuestionScenePainter oldDelegate) {
    return step != oldDelegate.step ||
        progress != oldDelegate.progress ||
        accent != oldDelegate.accent;
  }
}

class _SnapshotStrip extends StatelessWidget {
  final _JourneySnapshot snapshot;
  final Color accent;

  const _SnapshotStrip({required this.snapshot, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF102C25).withValues(alpha: 0.94),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: AppRadius.card,
            ),
            child: Icon(snapshot.icon, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PaycheckType.micro(color: Colors.white70),
                ),
                Text(
                  snapshot.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PaycheckType.bodyMedium(color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.info_outline_rounded, color: Colors.white, size: 19),
        ],
      ),
    );
  }
}

class _WhyOverlay extends StatelessWidget {
  final String chapter;
  final String helper;
  final Color accent;

  const _WhyOverlay({
    super.key,
    required this.chapter,
    required this.helper,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF102C25).withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: AppRadius.card,
                  ),
                  child: const Icon(
                    Icons.auto_awesome_outlined,
                    size: 19,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.close_rounded, color: Colors.white, size: 20),
              ],
            ),
            const Spacer(),
            Text(
              'Why $chapter matters',
              style: PaycheckType.heading().copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              helper,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: PaycheckType.caption(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

// Legacy compact renderer kept for narrow embedded surfaces.
// ignore: unused_element
class _SnapshotPanel extends StatelessWidget {
  final int step;
  final UserProfile profile;
  final _JourneySnapshot snapshot;
  final String chapter;
  final Color accent;

  // ignore: unused_element_parameter
  const _SnapshotPanel({
    required this.step,
    required this.profile,
    required this.snapshot,
    required this.chapter,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        chapter.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PaycheckType.sectionLabel(color: accent)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: accent,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  snapshot.label,
                  style:
                      PaycheckType.micro(color: PaycheckColors.textSecondary),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  height: 26,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        snapshot.value,
                        maxLines: 1,
                        style: PaycheckType.h2().copyWith(fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 102,
            height: 124,
            decoration: const BoxDecoration(
              color: PaycheckColors.bgSurface,
              borderRadius: AppRadius.card,
            ),
            child: _StepVisual(
              step: step,
              profile: profile,
              icon: snapshot.icon,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepVisual extends StatelessWidget {
  final int step;
  final UserProfile profile;
  final IconData icon;

  const _StepVisual({
    required this.step,
    required this.profile,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: switch (step) {
        0 => _IncomeBars(value: profile.annualCTC),
        1 => _EmploymentCard(
            salaried: profile.employmentType == EmploymentType.salaried,
          ),
        2 => const _CityLine(),
        3 => _HouseKey(active: profile.paysRent),
        4 => _ReceiptCheck(active: profile.hasHRA),
        5 => _LimitRing(value: profile.invested80C, maximum: 150000),
        6 => _HouseKey(active: profile.hasHomeLoan, loan: true),
        7 => _CoinStack(active: profile.hasNPS),
        8 => _ShieldCover(
            active: profile.hasHealthInsuranceSelf ||
                profile.hasHealthInsuranceParents,
          ),
        9 => _EducationStack(active: profile.hasEducationLoan),
        10 => _GivingReceipt(active: profile.hasDonations),
        _ => _FinalCheck(icon: icon),
      },
    );
  }
}

class _IncomeBars extends StatelessWidget {
  final int value;

  const _IncomeBars({required this.value});

  @override
  Widget build(BuildContext context) {
    final ratio = (value / 6000000).clamp(0.12, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '₹',
          style: PaycheckType.bodyStrong(color: PaycheckColors.textPrimary)
              .copyWith(
            fontSize: 25,
          ),
        ),
        const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _Bar(height: 22 + 20 * ratio),
            const SizedBox(width: 8),
            _Bar(height: 34 + 28 * ratio),
            const SizedBox(width: 8),
            _Bar(height: 48 + 30 * ratio, dark: true),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double height;
  final bool dark;

  const _Bar({required this.height, this.dark = false});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: dark ? PaycheckColors.textPrimary : PaycheckColors.bgCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            border: dark ? null : Border.all(color: PaycheckColors.border),
          ),
        ),
      );
}

class _EmploymentCard extends StatelessWidget {
  final bool salaried;

  const _EmploymentCard({required this.salaried});

  @override
  Widget build(BuildContext context) => Center(
        child: Transform.rotate(
          angle: -0.08,
          child: Container(
            width: 68,
            height: 88,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PaycheckColors.bgCard,
              borderRadius: AppRadius.card,
              border: Border.all(color: PaycheckColors.textPrimary, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  salaried ? Icons.badge_outlined : Icons.storefront_outlined,
                  size: 24,
                ),
                const Spacer(),
                Container(height: 5, color: PaycheckColors.textPrimary),
                const SizedBox(height: 4),
                Container(width: 32, height: 4, color: PaycheckColors.border),
              ],
            ),
          ),
        ),
      );
}

class _CityLine extends StatelessWidget {
  const _CityLine();

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.bottomCenter,
        children: [
          const Positioned(
              top: 4, right: 3, child: Icon(Icons.location_on, size: 24)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _building(38, 18),
              _building(66, 24, dark: true),
              _building(49, 18),
            ],
          ),
        ],
      );

  Widget _building(double height, double width, {bool dark = false}) =>
      Container(
        width: width,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: dark ? PaycheckColors.textPrimary : PaycheckColors.bgCard,
          border: Border.all(color: PaycheckColors.textPrimary),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
      );
}

class _HouseKey extends StatelessWidget {
  final bool active;
  final bool loan;

  const _HouseKey({required this.active, this.loan = false});

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.house_outlined,
              size: 74,
              color: active
                  ? PaycheckColors.textPrimary
                  : PaycheckColors.textMuted),
          Positioned(
            right: 0,
            bottom: 10,
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                  color: PaycheckColors.textPrimary, shape: BoxShape.circle),
              child: Icon(loan ? Icons.percent_rounded : Icons.key_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ],
      );
}

class _ReceiptCheck extends StatelessWidget {
  final bool active;

  const _ReceiptCheck({required this.active});

  @override
  Widget build(BuildContext context) => Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 60,
              height: 86,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: PaycheckColors.bgCard,
                  border: Border.all(color: PaycheckColors.border)),
              child: Column(
                  children: List.generate(
                      4,
                      (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                                height: 4,
                                color: i == 0
                                    ? PaycheckColors.textPrimary
                                    : PaycheckColors.border),
                          ))),
            ),
            Positioned(
                right: -12,
                bottom: -5,
                child: Icon(active ? Icons.check_circle : Icons.remove_circle,
                    size: 32)),
          ],
        ),
      );
}

class _LimitRing extends StatelessWidget {
  final int value;
  final int maximum;

  const _LimitRing({required this.value, required this.maximum});

  @override
  Widget build(BuildContext context) {
    final progress = (value / maximum).clamp(0.0, 1.0);
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.square(
          dimension: 76,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 9,
            strokeCap: StrokeCap.round,
            backgroundColor: PaycheckColors.bgCard,
            color: PaycheckColors.textPrimary,
          ),
        ),
        Text(
          '${(progress * 100).round()}%',
          style: PaycheckType.bodyStrong(color: PaycheckColors.textPrimary)
              .copyWith(
            fontSize: 17,
          ),
        ),
      ],
    );
  }
}

class _CoinStack extends StatelessWidget {
  final bool active;

  const _CoinStack({required this.active});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(Icons.savings_outlined,
              size: 48,
              color: active
                  ? PaycheckColors.textPrimary
                  : PaycheckColors.textMuted),
          const SizedBox(height: 8),
          ...List.generate(
              3,
              (i) => Container(
                    width: 62 - i * 7,
                    height: 9,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                        color: i == 0
                            ? PaycheckColors.textPrimary
                            : PaycheckColors.bgCard,
                        borderRadius: AppRadius.pill,
                        border: Border.all(color: PaycheckColors.textPrimary)),
                  )),
        ],
      );
}

class _ShieldCover extends StatelessWidget {
  final bool active;

  const _ShieldCover({required this.active});

  @override
  Widget build(BuildContext context) => Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.shield_outlined,
                size: 82,
                color: active
                    ? PaycheckColors.textPrimary
                    : PaycheckColors.textMuted),
            const Icon(Icons.add_rounded, size: 30),
          ],
        ),
      );
}

class _EducationStack extends StatelessWidget {
  final bool active;

  const _EducationStack({required this.active});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school_outlined,
              size: 49,
              color: active
                  ? PaycheckColors.textPrimary
                  : PaycheckColors.textMuted),
          const SizedBox(height: 8),
          Container(width: 70, height: 9, color: PaycheckColors.textPrimary),
          const SizedBox(height: 4),
          Container(width: 58, height: 8, color: PaycheckColors.bgCard),
        ],
      );
}

class _GivingReceipt extends StatelessWidget {
  final bool active;

  const _GivingReceipt({required this.active});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 66,
          height: 94,
          decoration: BoxDecoration(
              color: PaycheckColors.bgCard,
              border: Border.all(color: PaycheckColors.textPrimary)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(active ? Icons.favorite : Icons.favorite_border, size: 32),
              const SizedBox(height: 12),
              Container(
                  width: 36, height: 5, color: PaycheckColors.textPrimary),
              const SizedBox(height: 4),
              Container(width: 26, height: 4, color: PaycheckColors.border),
            ],
          ),
        ),
      );
}

class _FinalCheck extends StatelessWidget {
  final IconData icon;

  const _FinalCheck({required this.icon});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(
              color: PaycheckColors.textPrimary, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 38),
        ),
      );
}

// ignore: unused_element
class _WhyPanel extends StatelessWidget {
  final String chapter;
  final String helper;
  final Color accent;

  // ignore: unused_element_parameter
  const _WhyPanel({
    required this.chapter,
    required this.helper,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: AppRadius.card,
            ),
            child: const Icon(
              Icons.auto_awesome_outlined,
              size: 19,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Why $chapter matters',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: PaycheckType.heading().copyWith(fontSize: 16),
                      ),
                    ),
                    Icon(Icons.close_rounded, size: 17, color: accent),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  helper,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PaycheckType.micro(
                    color: PaycheckColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneySnapshot {
  final String label;
  final String value;
  final IconData icon;

  const _JourneySnapshot({
    required this.label,
    required this.value,
    required this.icon,
  });

  static final _money = NumberFormat.decimalPattern('en_IN');

  static String _rupees(int value) => '₹${_money.format(value)}';

  static _JourneySnapshot forStep(int step, UserProfile profile) {
    switch (step) {
      case 0:
        return _JourneySnapshot(
          label: 'Income base',
          value: '${_rupees(profile.annualCTC)} a year',
          icon: Icons.receipt_long_outlined,
        );
      case 1:
        return _JourneySnapshot(
          label: 'How you earn',
          value: profile.employmentType == EmploymentType.salaried
              ? 'Salaried income'
              : 'Independent income',
          icon: Icons.work_outline_rounded,
        );
      case 2:
        return _JourneySnapshot(
          label: 'Your tax city',
          value: profile.isMetroCity
              ? '${profile.city} · Metro HRA'
              : '${profile.city} · Non-metro HRA',
          icon: Icons.location_city_outlined,
        );
      case 3:
        return _JourneySnapshot(
          label: 'Rent trail',
          value: profile.paysRent
              ? '${_rupees(profile.monthlyRent)} each month'
              : 'No rent added',
          icon: Icons.key_outlined,
        );
      case 4:
        return _JourneySnapshot(
          label: 'Payslip signal',
          value: profile.hasHRA ? 'HRA found' : 'No HRA recorded',
          icon: Icons.home_work_outlined,
        );
      case 5:
        return _JourneySnapshot(
          label: '80C folder',
          value: '${_rupees(profile.invested80C)} of ₹1,50,000',
          icon: Icons.folder_copy_outlined,
        );
      case 6:
        return _JourneySnapshot(
          label: 'Property trail',
          value: profile.hasHomeLoan
              ? '${_rupees(profile.homeLoanInterest)} interest'
              : 'No home loan added',
          icon: Icons.house_outlined,
        );
      case 7:
        return _JourneySnapshot(
          label: 'Retirement pocket',
          value: profile.hasNPS
              ? '${_rupees(profile.npsExtraContribution)} extra NPS'
              : 'No extra NPS added',
          icon: Icons.savings_outlined,
        );
      case 8:
        final covered =
            profile.hasHealthInsuranceSelf || profile.hasHealthInsuranceParents;
        return _JourneySnapshot(
          label: 'Health cover',
          value: covered ? 'Policy cover found' : 'No cover added yet',
          icon: Icons.health_and_safety_outlined,
        );
      case 9:
        return _JourneySnapshot(
          label: 'Education interest',
          value: profile.hasEducationLoan
              ? '${_rupees(profile.educationLoanInterest)} recorded'
              : 'No education loan',
          icon: Icons.school_outlined,
        );
      case 10:
        return _JourneySnapshot(
          label: 'Giving record',
          value: profile.hasDonations
              ? '${_rupees(profile.donationAmount)} donated'
              : 'No donations added',
          icon: Icons.volunteer_activism_outlined,
        );
      default:
        return _JourneySnapshot(
          label: 'Final profile check',
          value: 'Age band: ${profile.ageGroup.label}',
          icon: Icons.verified_outlined,
        );
    }
  }
}
