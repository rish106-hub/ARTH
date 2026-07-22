import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AuthMotionScene extends StatefulWidget {
  final bool isSignUp;

  const AuthMotionScene({super.key, required this.isSignUp});

  @override
  State<AuthMotionScene> createState() => _AuthMotionSceneState();
}

class _AuthMotionSceneState extends State<AuthMotionScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final animation =
        reduceMotion ? const AlwaysStoppedAnimation<double>(0.45) : _controller;
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : AppMotion.medium,
        child: SizedBox(
          key: ValueKey(widget.isSignUp),
          width: double.infinity,
          height: 196,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) => CustomPaint(
              isComplex: true,
              willChange: !reduceMotion,
              painter: _AuthScenePainter(
                progress: animation.value,
                isSignUp: widget.isSignUp,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthScenePainter extends CustomPainter {
  final double progress;
  final bool isSignUp;

  const _AuthScenePainter({required this.progress, required this.isSignUp});

  static const ink = Color(0xFF14213D);
  static const blue = Color(0xFF4A66F0);
  static const green = Color(0xFF12A875);
  static const coral = Color(0xFFFF6B4A);
  static const yellow = Color(0xFFF2B84B);
  static const paper = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    _rect(
      canvas,
      Offset.zero & size,
      isSignUp ? const Color(0xFFEAF6F1) : const Color(0xFFEEF1FF),
      8,
    );
    if (isSignUp) {
      _paintSignUp(canvas, size);
    } else {
      _paintSignIn(canvas, size);
    }
  }

  void _paintSignUp(Canvas canvas, Size size) {
    final wave = math.sin(progress * math.pi * 2);
    _rect(canvas, Rect.fromLTWH(size.width * .34, 25, size.width * .34, 146),
        paper, 12);
    _circle(canvas, Offset(size.width * .51, 58), 19, blue);
    _line(canvas, Offset(size.width * .43, 91), Offset(size.width * .59, 91),
        ink, 7);
    _line(canvas, Offset(size.width * .40, 110), Offset(size.width * .62, 110),
        ink.withValues(alpha: .22), 5);
    _line(canvas, Offset(size.width * .40, 126), Offset(size.width * .56, 126),
        ink.withValues(alpha: .22), 5);
    _rect(canvas, Rect.fromLTWH(size.width * .42, 143, size.width * .18, 10),
        green, 5);

    final colors = [yellow, coral, blue];
    for (var i = 0; i < 3; i++) {
      final phase = (progress + i * .22) % 1;
      final x = 24 + phase * (size.width * .25);
      final y = 42 + i * 43 + wave * 3;
      _circle(canvas, Offset(x, y), 13, colors[i]);
      _line(canvas, Offset(x + 20, y), Offset(x + 54, y),
          ink.withValues(alpha: .35), 5);
    }

    final checkY = 52 + ((progress + .25) % 1) * 82;
    _circle(canvas, Offset(size.width * .79, checkY), 21, green);
    _check(canvas, Offset(size.width * .79, checkY), paper);
  }

  void _paintSignIn(Canvas canvas, Size size) {
    final wave = math.sin(progress * math.pi * 2);
    final center = Offset(size.width * .5, 95);
    final shield = Path()
      ..moveTo(center.dx, 22)
      ..lineTo(center.dx + 62, 45)
      ..lineTo(center.dx + 47, 133)
      ..quadraticBezierTo(center.dx, 174, center.dx - 47, 133)
      ..lineTo(center.dx - 62, 45)
      ..close();
    canvas.drawPath(shield, Paint()..color = paper);
    canvas.drawPath(
      shield,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    _circle(canvas, Offset(center.dx, 91), 24, blue);
    _rect(
        canvas,
        Rect.fromCenter(center: Offset(center.dx, 123), width: 12, height: 32),
        blue,
        6);
    _rect(canvas, Rect.fromLTWH(center.dx - 20, 65 - wave * 4, 40, 42),
        Colors.transparent, 18,
        stroke: ink);

    for (var i = 0; i < 4; i++) {
      final angle = progress * math.pi * 2 + i * math.pi / 2;
      final point = Offset(
        center.dx + math.cos(angle) * size.width * .32,
        center.dy + math.sin(angle) * 64,
      );
      _circle(
          canvas,
          point,
          i.isEven ? 12 : 9,
          i == 0
              ? coral
              : i == 1
                  ? green
                  : yellow);
    }
  }

  void _circle(Canvas canvas, Offset center, double radius, Color color) =>
      canvas.drawCircle(center, radius, Paint()..color = color);

  void _rect(Canvas canvas, Rect rect, Color color, double radius,
      {Color? stroke}) {
    final paint = Paint()..color = stroke ?? color;
    if (stroke != null) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
  }

  void _line(
      Canvas canvas, Offset start, Offset end, Color color, double width) {
    canvas.drawLine(
        start,
        end,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round);
  }

  void _check(Canvas canvas, Offset center, Color color) {
    final path = Path()
      ..moveTo(center.dx - 9, center.dy)
      ..lineTo(center.dx - 2, center.dy + 7)
      ..lineTo(center.dx + 11, center.dy - 8);
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_AuthScenePainter oldDelegate) =>
      progress != oldDelegate.progress || isSignUp != oldDelegate.isSignUp;
}
