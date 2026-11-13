import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pose.dart';

/// Draws Nox (style A: round, plush-like), from the reference sketch.
///
/// Drawing happens in the sketch's own coordinates (the owl's feet are at
/// (200, 408)), then scaled down by [owlScale] around [feet].
class OwlPainter extends CustomPainter {
  OwlPainter({required this.pose, required this.feet, this.owlScale = 0.4})
      : super(repaint: pose);

  final NoxPose pose;

  /// Position of the feet inside the widget, in logical pixels.
  final Offset feet;
  final double owlScale;

  static const _plumage = Color(0xFF8B6B4F);
  static const _wing = Color(0xFF6E533D);
  static const _belly = Color(0xFFECDCBF);
  static const _chevron = Color(0xFFC9AD85);
  static const _faceDisc = Color(0xFFF5E9D3);
  static const _iris = Color(0xFFF2B53A);
  static const _pupil = Color(0xFF1A120C);
  static const _beak = Color(0xFFF0973A);
  static const _cheek = Color(0x73FF8FA3);
  static const _lid = Color(0xFF3A2A1C);

  @override
  void paint(Canvas canvas, Size size) {
    if (pose.hidden) return;
    if (pose.island < 1) _owl(canvas, size);
    if (pose.island > 0) _islandPill(canvas);
  }

  void _owl(Canvas canvas, Size size) {
    final breath = 1 + 0.015 * math.sin(pose.time * 2.2);
    final fade = 1 - pose.island;
    if (fade < 1) {
      canvas.saveLayer(Offset.zero & size,
          Paint()..color = Color.fromRGBO(0, 0, 0, fade));
    }

    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    canvas.rotate(pose.tilt);
    canvas.scale(owlScale, owlScale * breath);
    canvas.translate(-200, -408);

    _wings(canvas);
    _tufts(canvas);
    _body(canvas);
    _face(canvas);
    _feet(canvas);
    if (pose.carrying) _envelope(canvas);
    if (pose.sleeping) _zzz(canvas);

    canvas.restore();
    if (fade < 1) canvas.restore();
  }

  static const _night = Color(0xFF16110D);

  /// The "dynamic island": a dark pill at the top of the screen where only
  /// Nox's eyes show. Opened (expand = 1) when he is called.
  void _islandPill(Canvas canvas) {
    final a = pose.island;
    final e = pose.expand;
    final size = islandSize(a, e);
    final rect = Rect.fromLTWH(
        feet.dx - size.width / 2, kIslandTop, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2));

    canvas.drawRRect(rrect, _fill(_night.withValues(alpha: a)));
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _iris.withValues(alpha: 0.25 * a));
    if (a < 0.6) return;
    final eyesAlpha = ((a - 0.6) / 0.4).clamp(0.0, 1.0);

    final r = 6 + 6 * e;
    final cy = rect.top + (a * 15) + e * 6;
    final spread = 14 + 8 * e;
    for (final side in [-1.0, 1.0]) {
      final c = Offset(rect.center.dx + side * spread, cy);
      _islandEye(canvas, c, r, eyesAlpha);
    }
    if (e > 0.3) {
      final beakAlpha = ((e - 0.3) / 0.7).clamp(0.0, 1.0) * eyesAlpha;
      final top = cy + r + 3;
      final beak = Path()
        ..moveTo(rect.center.dx - 4, top)
        ..lineTo(rect.center.dx + 4, top)
        ..lineTo(rect.center.dx, top + 7)
        ..close();
      canvas.drawPath(beak, _fill(_beak.withValues(alpha: beakAlpha)));
    }
  }

  void _islandEye(Canvas canvas, Offset c, double r, double alpha) {
    final iris = _iris.withValues(alpha: alpha);
    final line = Paint()
      ..color = iris
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (pose.happy) {
      canvas.drawPath(
          Path()
            ..moveTo(c.dx - r, c.dy + r * 0.3)
            ..quadraticBezierTo(c.dx, c.dy - r * 0.8, c.dx + r, c.dy + r * 0.3),
          line);
      return;
    }
    if (pose.sleeping || pose.eyeOpen < 0.15) {
      canvas.drawPath(
          Path()
            ..moveTo(c.dx - r, c.dy)
            ..quadraticBezierTo(c.dx, c.dy + r * 0.6, c.dx + r, c.dy),
          line);
      return;
    }
    canvas.drawCircle(c, r, _fill(iris));
    final p = c + pose.look * (r * 0.35);
    canvas.drawCircle(p, r * 0.6, _fill(_pupil.withValues(alpha: alpha)));
    canvas.drawCircle(p + Offset(-r * 0.25, -r * 0.25), r * 0.2,
        _fill(Colors.white.withValues(alpha: alpha)));
  }

  Paint _fill(Color c) => Paint()
    ..color = c
    ..isAntiAlias = true;

  void _wings(Canvas canvas) {
    final angle = pose.wingSpread * 1.15 + pose.wingFlap;
    for (final side in [-1.0, 1.0]) {
      canvas.save();
      final shoulder = Offset(200 + side * 82, 245);
      canvas.translate(shoulder.dx, shoulder.dy);
      canvas.rotate(-side * angle);
      canvas.translate(-shoulder.dx, -shoulder.dy);
      final c = Offset(200 + side * 102, 300);
      canvas.translate(c.dx, c.dy);
      canvas.rotate(-side * 14 * math.pi / 180);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 60, height: 136),
          _fill(_wing));
      canvas.restore();
    }
  }

  void _tufts(Canvas canvas) {
    final dx = pose.headTurn * 6;
    final left = Path()
      ..moveTo(118 + dx, 200)
      ..quadraticBezierTo(100 + dx, 128, 134 + dx, 140)
      ..quadraticBezierTo(152 + dx, 160, 168 + dx, 172)
      ..close();
    final right = Path()
      ..moveTo(282 + dx, 200)
      ..quadraticBezierTo(300 + dx, 128, 266 + dx, 140)
      ..quadraticBezierTo(248 + dx, 160, 232 + dx, 172)
      ..close();
    canvas.drawPath(left, _fill(_plumage));
    canvas.drawPath(right, _fill(_plumage));
  }

  void _body(Canvas canvas) {
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(200, 280), width: 220, height: 236),
        _fill(_plumage));
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(200, 320), width: 136, height: 144),
        _fill(_belly));
    final stroke = Paint()
      ..color = _chevron
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const rows = [
      [170.0, 305.0], [196.0, 305.0], [222.0, 305.0],
      [183.0, 328.0], [209.0, 328.0],
      [170.0, 351.0], [196.0, 351.0], [222.0, 351.0],
    ];
    for (final r in rows) {
      final p = Path()
        ..moveTo(r[0], r[1])
        ..quadraticBezierTo(r[0] + 8, r[1] + 8, r[0] + 16, r[1]);
      canvas.drawPath(p, stroke);
    }
  }

  void _face(Canvas canvas) {
    final dx = pose.headTurn * 12;
    canvas.drawCircle(Offset(160 + dx, 232), 52, _fill(_faceDisc));
    canvas.drawCircle(Offset(240 + dx, 232), 52, _fill(_faceDisc));

    _eye(canvas, Offset(162 + dx, 232));
    _eye(canvas, Offset(238 + dx, 232));

    final beak = Path()
      ..moveTo(190 + dx, 262)
      ..quadraticBezierTo(200 + dx, 258, 210 + dx, 262)
      ..quadraticBezierTo(204 + dx, 282, 200 + dx, 284)
      ..quadraticBezierTo(196 + dx, 282, 190 + dx, 262)
      ..close();
    canvas.drawPath(beak, _fill(_beak));

    final cheekAlpha = pose.happy ? 1.0 : 0.75;
    final cheek = _fill(_cheek.withValues(alpha: _cheek.a * cheekAlpha));
    canvas.drawOval(
        Rect.fromCenter(center: Offset(132 + dx, 285), width: 28, height: 16), cheek);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(268 + dx, 285), width: 28, height: 16), cheek);
  }

  void _eye(Canvas canvas, Offset c) {
    final lidStroke = Paint()
      ..color = _lid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    if (pose.happy) {
      // ^ ^
      final p = Path()
        ..moveTo(c.dx - 24, c.dy + 6)
        ..quadraticBezierTo(c.dx, c.dy - 18, c.dx + 24, c.dy + 6);
      canvas.drawPath(p, lidStroke);
      return;
    }
    if (pose.sleeping || pose.eyeOpen < 0.15) {
      final p = Path()
        ..moveTo(c.dx - 24, c.dy)
        ..quadraticBezierTo(c.dx, c.dy + 14, c.dx + 24, c.dy);
      canvas.drawPath(p, lidStroke);
      return;
    }

    final irisR = pose.surprised ? 38.0 : 36.0;
    final pupilR = pose.surprised ? 16.0 : 26.0;
    final shift = pose.look * (irisR - pupilR - 2);
    canvas.drawCircle(c, irisR, _fill(_iris));
    final p = c + Offset(0, 2) + shift;
    canvas.drawCircle(p, pupilR, _fill(_pupil));
    final white = _fill(Colors.white);
    canvas.drawCircle(p + const Offset(-10, -11), pose.surprised ? 6 : 9, white);
    canvas.drawCircle(p + const Offset(8, 8), 4, white);

    if (pose.eyeOpen < 1) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: irisR + 1)));
      final h = (irisR * 2 + 2) * (1 - pose.eyeOpen);
      canvas.drawRect(
          Rect.fromLTWH(c.dx - irisR - 1, c.dy - irisR - 1, irisR * 2 + 2, h),
          _fill(_faceDisc));
      canvas.restore();
    }
  }

  /// The envelope Nox holds in his beak when he has news for you.
  void _envelope(Canvas canvas) {
    final dx = pose.headTurn * 12;
    final r = Rect.fromCenter(center: Offset(200 + dx, 304), width: 70, height: 46);
    final paper = RRect.fromRectAndRadius(r, const Radius.circular(5));
    final edge = Paint()
      ..color = _chevron
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(paper, _fill(Colors.white));
    canvas.drawRRect(paper, edge);
    final flap = Path()
      ..moveTo(r.left + 3, r.top + 3)
      ..lineTo(r.center.dx, r.center.dy + 4)
      ..lineTo(r.right - 3, r.top + 3);
    canvas.drawPath(flap, edge);
  }

  void _feet(Canvas canvas) {
    if (pose.feetTucked) return;
    final f = _fill(_beak);
    for (final x in [165.0, 178.0, 222.0, 235.0]) {
      final y = (x == 165 || x == 235) ? 400.0 : 402.0;
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 14, height: 18), f);
    }
  }

  void _zzz(Canvas canvas) {
    for (var i = 0; i < 3; i++) {
      final phase = (pose.time * 0.5 + i / 3) % 1.0;
      final tp = TextPainter(
        text: TextSpan(
          text: 'z',
          style: TextStyle(
            color: Colors.white.withValues(alpha: (1 - phase) * 0.9),
            fontSize: 30 + phase * 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(290 + phase * 40, 170 - phase * 90));
    }
  }

  @override
  bool shouldRepaint(OwlPainter old) =>
      old.pose != pose || old.feet != feet || old.owlScale != owlScale;
}
