import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/paycheck_theme.dart';

/// Animates counting from 0 to [value] over [duration].
class AnimatedRupeeNumber extends StatefulWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;
  final String prefix;

  const AnimatedRupeeNumber({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 1800),
    this.prefix = '₹',
  });

  @override
  State<AnimatedRupeeNumber> createState() => _AnimatedRupeeNumberState();
}

class _AnimatedRupeeNumberState extends State<AnimatedRupeeNumber>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  final _fmt = NumberFormat('#,##,##0', 'en_IN');

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(AnimatedRupeeNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _ctrl.reset();
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style =
        widget.style ?? PaycheckType.display(color: PaycheckColors.gold);

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final current = (_anim.value * widget.value).round();
        return Text(
          '${widget.prefix} ${_fmt.format(current)}',
          style: style,
          textAlign: TextAlign.center,
        );
      },
    );
  }
}

/// Static formatted rupee text
class RupeeText extends StatelessWidget {
  final int amount;
  final TextStyle? style;
  final String prefix;

  const RupeeText({
    super.key,
    required this.amount,
    this.style,
    this.prefix = '₹',
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##,##0', 'en_IN');
    return Text(
      '$prefix ${fmt.format(amount)}',
      style: style ?? PaycheckType.h2(color: PaycheckColors.gold),
    );
  }
}

String formatRupees(int amount) {
  final fmt = NumberFormat('#,##,##0', 'en_IN');
  return '₹ ${fmt.format(amount)}';
}

String formatRupeesCompact(int amount) {
  if (amount >= 100000) {
    double lakhs = amount / 100000;
    if (lakhs == lakhs.roundToDouble()) {
      return '₹ ${lakhs.round()} L';
    }
    return '₹ ${lakhs.toStringAsFixed(1)} L';
  }
  if (amount >= 1000) {
    double k = amount / 1000;
    return '₹ ${k.toStringAsFixed(0)}K';
  }
  return '₹ $amount';
}
