import 'package:flutter/material.dart';

import 'annotations.dart';

void paintDraw(Canvas canvas, Size size, DrawAnn a) {
  final paint = Paint()
    ..color = a.color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = (a.width * size.width).clamp(1.0, 200.0);
  for (final s in a.strokes) {
    canvas.drawPath(strokePath(s, size), paint);
  }
}

/// Text style shared by the on-screen text box and the exported page, so both wrap the same way.
TextStyle annotationTextStyle(TextAnn a, double pageWidth) => TextStyle(
      fontSize: a.size * pageWidth,
      color: a.color,
      height: textLineHeight,
      leadingDistribution: TextLeadingDistribution.even,
    );

void paintText(Canvas canvas, Size size, TextAnn a) {
  if (a.blank) return;
  final px = a.size * size.width;
  final padX = px * textPadX;
  final padY = px * textPadY;
  final tp = TextPainter(
    text: TextSpan(text: a.text, style: annotationTextStyle(a, size.width)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: (a.w * size.width - padX * 2).clamp(1.0, double.infinity));
  tp.paint(canvas, Offset(a.x * size.width + padX, a.y * size.height + padY));
  tp.dispose();
}

/// Paints the drawings of one page (text boxes are real text fields on screen).
class DrawLayerPainter extends CustomPainter {
  DrawLayerPainter(this.items, {this.live, this.liveColor = Colors.black, this.liveWidth = 0.004});

  final List<DrawAnn> items;
  final List<Offset>? live;
  final Color liveColor;
  final double liveWidth;

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in items) {
      paintDraw(canvas, size, a);
    }
    final l = live;
    if (l != null && l.isNotEmpty) {
      paintDraw(
        canvas,
        size,
        DrawAnn(id: 'live', page: 0, color: liveColor, strokes: [l], width: liveWidth),
      );
    }
  }

  @override
  bool shouldRepaint(covariant DrawLayerPainter old) => true;
}
