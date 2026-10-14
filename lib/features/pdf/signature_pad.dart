import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'annotations.dart';

const padColors = [Color(0xFF111111), Color(0xFF1A56DB), Color(0xFFD61F1F)];
const _penSizes = [2.0, 3.0, 5.0];

/// A signature drawn by the user. Strokes are in "signature widths": x from 0 to 1, y from 0 to [ratio].
class SignatureResult {
  const SignatureResult({
    required this.strokes,
    required this.width,
    required this.color,
    required this.ratio,
    this.remember = false,
  });

  final List<List<Offset>> strokes;
  final double width;
  final Color color;
  final double ratio;

  /// The user asked to keep it for the next documents.
  final bool remember;
}

class _Stroke {
  _Stroke(this.color, this.pen);

  final Color color;
  final double pen;
  final List<Offset> points = [];
}

/// Full-screen sheet to draw a signature with a finger or stylus.
Future<SignatureResult?> showSignaturePad(BuildContext context, {Color? initialColor}) {
  return showModalBottomSheet<SignatureResult>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    builder: (_) => _SignaturePad(initialColor: initialColor),
  );
}

class _SignaturePad extends StatefulWidget {
  const _SignaturePad({this.initialColor});

  final Color? initialColor;

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final List<_Stroke> _strokes = [];
  _Stroke? _current;
  late Color _color = padColors.contains(widget.initialColor) ? widget.initialColor! : padColors[1];
  double _pen = 3;
  bool _remember = true;
  Size _canvas = Size.zero;

  void _down(PointerDownEvent e) {
    setState(() => _current = _Stroke(_color, _pen)..points.add(e.localPosition));
  }

  void _move(PointerMoveEvent e) {
    final c = _current;
    if (c == null) return;
    setState(() => c.points.add(e.localPosition));
  }

  void _up(PointerEvent e) {
    final c = _current;
    if (c == null) return;
    setState(() {
      _strokes.add(c);
      _current = null;
    });
  }

  void _finish() {
    if (_strokes.isEmpty || _canvas.width <= 0) return;
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final s in _strokes) {
      for (final p in s.points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    // a little margin around the ink, then everything in "signature widths"
    final margin = _pen * 2;
    minX -= margin;
    minY -= margin;
    maxX += margin;
    maxY += margin;
    final w = (maxX - minX).clamp(1.0, double.infinity);
    final h = (maxY - minY).clamp(1.0, double.infinity);
    final lastColor = _strokes.last.color;
    Navigator.pop(
      context,
      SignatureResult(
        strokes: [
          for (final s in _strokes) [for (final p in s.points) Offset((p.dx - minX) / w, (p.dy - minY) / w)],
        ],
        width: _pen / w,
        color: lastColor,
        ratio: h / w,
        remember: _remember,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final all = [..._strokes, if (_current != null) _current!];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('ចុះហត្ថលេខា', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const Text('ប្រើម្រាមដៃ ឬប៊ិចសរសេរហត្ថលេខាខាងក្រោម', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final height = (MediaQuery.of(context).size.height * 0.38).clamp(180.0, 360.0);
              _canvas = Size(c.maxWidth, height);
              return Container(
                height: height,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _down,
                    onPointerMove: _move,
                    onPointerUp: _up,
                    onPointerCancel: _up,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _PadPainter(all),
                      child: all.isEmpty
                          ? const Center(
                              child: Text('សរសេរទីនេះ', style: TextStyle(color: AppColors.other, fontSize: 18)),
                            )
                          : null,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final c in padColors)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: c == _color ? AppColors.primary : Colors.transparent, width: 3),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              SegmentedButton<double>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  for (final p in _penSizes)
                    ButtonSegment(value: p, label: Icon(Icons.circle, size: 4 + p * 2)),
                ],
                selected: {_pen},
                onSelectionChanged: (v) => setState(() => _pen = v.first),
              ),
            ],
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _remember,
            onChanged: (v) => setState(() => _remember = v),
            title: const Text('ចងចាំហត្ថលេខានេះសម្រាប់ឯកសារក្រោយៗ'),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _strokes.isEmpty ? null : () => setState(() => _strokes.clear()),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('លុប'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _strokes.isEmpty ? null : _finish,
                  icon: const Icon(Icons.check),
                  label: const Text('ប្រើហត្ថលេខានេះ'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.strokes);

  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.pen;
      // reuse the page smoothing with fractions of 1px so the preview matches what is placed
      canvas.drawPath(strokePath(s.points.map((p) => Offset(p.dx, p.dy)).toList(), const Size(1, 1)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PadPainter old) => true;
}
