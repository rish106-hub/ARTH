import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ArthBrandMark extends StatelessWidget {
  final double size;
  final bool showWordmark;
  final TextStyle? wordmarkStyle;
  final double spacing;

  const ArthBrandMark({
    super.key,
    this.size = 42,
    this.showWordmark = true,
    this.wordmarkStyle,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    final mark = RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _ArthGlyphPainter(),
        ),
      ),
    );

    if (!showWordmark) {
      return mark;
    }

    final effectiveWordmarkStyle = wordmarkStyle ??
        AppTextStyles.h3(
          color: AppColors.textPrimary,
        ).copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mark,
        SizedBox(width: spacing),
        Text(
          'ARTH',
          style: effectiveWordmarkStyle,
          semanticsLabel: 'ARTH',
        ),
      ],
    );
  }
}

class _ArthGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final shortest = size.shortestSide;
    final rect = Offset.zero & size;
    final shell = RRect.fromRectAndRadius(
      rect,
      Radius.circular(shortest * 0.24),
    );

    canvas.drawRRect(
      shell,
      Paint()..color = AppColors.ink,
    );

    final letterPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = shortest * 0.115
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawLine(
      Offset(size.width * 0.27, size.height * 0.75),
      Offset(size.width * 0.46, size.height * 0.25),
      letterPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.54, size.height * 0.25),
      Offset(size.width * 0.76, size.height * 0.75),
      letterPaint,
    );

    final reconcilePaint = Paint()
      ..color = AppColors.readiness
      ..style = PaintingStyle.stroke
      ..strokeWidth = shortest * 0.09
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.35, size.height * 0.57),
      Offset(size.width * 0.67, size.height * 0.57),
      reconcilePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
