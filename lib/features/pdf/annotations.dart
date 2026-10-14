import 'dart:math' as math;
import 'dart:ui';

/// Every annotation keeps positions as fractions of its page (x -> page width, y -> page height)
/// and sizes as fractions of the page width, so it stays in place at any zoom level
/// (same model as the web annotator).
const double basePageWidth = 595; // A4 width in pt: font sizes / pen widths are entered relative to it
const double textLineHeight = 1.35;
const double textPadX = 0.3; // em
const double textPadY = 0.15; // em

int _counter = 0;
String newAnnId() => 'a${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(++_counter).toRadixString(36)}';

double clampD(double v, double min, double max) => math.min(math.max(v, min), max);

sealed class Ann {
  const Ann({required this.id, required this.page, required this.color});

  final String id;
  final int page; // 1-based
  final Color color;

  Ann moved(int page, double x, double y);
}

class TextAnn extends Ann {
  const TextAnn({
    required super.id,
    required super.page,
    required super.color,
    required this.x,
    required this.y,
    required this.w,
    required this.text,
    required this.size,
  });

  final double x;
  final double y;
  final double w; // fraction of page width
  final String text;
  final double size; // fraction of page width (font px = size * page width px)

  bool get blank => text.trim().isEmpty;

  TextAnn copyWith({double? x, double? y, double? w, String? text, double? size, Color? color, int? page}) => TextAnn(
        id: id,
        page: page ?? this.page,
        color: color ?? this.color,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        text: text ?? this.text,
        size: size ?? this.size,
      );

  @override
  TextAnn moved(int page, double nx, double ny) =>
      copyWith(page: page, x: clampD(nx, 0, math.max(0, 1 - w)), y: clampD(ny, 0, 0.98));
}

class DrawAnn extends Ann {
  const DrawAnn({
    required super.id,
    required super.page,
    required super.color,
    required this.strokes,
    required this.width,
  });

  final List<List<Offset>> strokes; // page fractions
  final double width; // pen width, fraction of page width

  Rect get bounds {
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final s in strokes) {
      for (final p in s) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    if (minX == double.infinity) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  DrawAnn copyWith({List<List<Offset>>? strokes, double? width, Color? color, int? page}) => DrawAnn(
        id: id,
        page: page ?? this.page,
        color: color ?? this.color,
        strokes: strokes ?? this.strokes,
        width: width ?? this.width,
      );

  @override
  DrawAnn moved(int page, double x, double y) {
    final b = bounds;
    final nx = clampD(x, 0, math.max(0, 1 - b.width));
    final ny = clampD(y, 0, math.max(0, 1 - b.height));
    final dx = nx - b.left;
    final dy = ny - b.top;
    return copyWith(
      page: page,
      strokes: [
        for (final s in strokes) [for (final p in s) Offset(p.dx + dx, p.dy + dy)],
      ],
    );
  }

  /// Scale around ([ox], [oy]) - used by the resize handle.
  DrawAnn scaled(double factor, double ox, double oy) => copyWith(
        width: width * factor,
        strokes: [
          for (final s in strokes) [for (final p in s) Offset(ox + (p.dx - ox) * factor, oy + (p.dy - oy) * factor)],
        ],
      );
}

/// Top-left corner of any annotation.
Offset originOf(Ann a) {
  if (a is TextAnn) return Offset(a.x, a.y);
  final b = (a as DrawAnn).bounds;
  return Offset(b.left, b.top);
}

/// Smooth path (quadratic curves through the midpoints) for one stroke, in pixels of [size].
Path strokePath(List<Offset> pts, Size size) {
  final path = Path();
  if (pts.isEmpty) return path;
  Offset px(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
  final first = px(pts.first);
  path.moveTo(first.dx, first.dy);
  if (pts.length == 1) {
    path.lineTo(first.dx, first.dy);
    return path;
  }
  for (var i = 1; i < pts.length - 1; i++) {
    final p = px(pts[i]);
    final n = px(pts[i + 1]);
    path.quadraticBezierTo(p.dx, p.dy, (p.dx + n.dx) / 2, (p.dy + n.dy) / 2);
  }
  final last = px(pts.last);
  path.lineTo(last.dx, last.dy);
  return path;
}
