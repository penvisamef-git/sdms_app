import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/select_sheet.dart';
import 'annotation_painter.dart';
import 'annotations.dart';
import 'pdf_export.dart';
import 'signature_pad.dart';
import 'signature_store.dart';

enum _Tool { hand, text, pen }

const _colors = [
  Color(0xFF111111),
  Color(0xFF1A56DB),
  Color(0xFFD61F1F),
  Color(0xFF0E8A3A),
  Color(0xFF7C3AED),
  Color(0xFFE08A00),
];
const _fontSizes = [10, 12, 14, 16, 18, 20, 24, 28, 32, 40];
const _penWidths = [1, 2, 3, 5, 8];
const _defaultTextW = 0.35;
const _zoomMin = 0.6;
const _zoomMax = 3.0;
const _historyMax = 50;
const _gap = 12.0;

String _errText(Object e) => e.toString().replaceFirst('Exception: ', '');

/// Write / sign on a PDF with a finger or stylus: text boxes, pen, signature.
/// Pops with the fresh file info when saved ([onSave] stores the signed PDF), or null.
class PdfAnnotatorPage extends StatefulWidget {
  const PdfAnnotatorPage({
    super.key,
    required this.file,
    required this.onSave,
    this.blockedReason = '',
  });

  final Json file;

  /// Uploads the signed PDF and replaces the original file; returns the new file info.
  final Future<Json> Function(Uint8List bytes, Json file) onSave;

  /// When not empty the annotations can be made but not saved (and this says why).
  final String blockedReason;

  @override
  State<PdfAnnotatorPage> createState() => _PdfAnnotatorPageState();
}

class _LiveStroke {
  _LiveStroke(this.page, this.points);

  final int page;
  final List<Offset> points;
}

class _PdfAnnotatorPageState extends State<PdfAnnotatorPage> {
  Uint8List? _bytes;
  PdfDocument? _doc;
  List<Size> _pageSizes = [];
  String _loadError = '';
  double? _downloadPct;

  List<Ann> _anns = [];
  final List<List<Ann>> _history = [];
  _Tool _tool = _Tool.hand;
  Color _color = _colors[1];
  int _fontPt = 16;
  int _penPt = 2;
  String? _selectedId;
  String? _focusId;
  double _zoom = 1;
  bool _lockScroll = false;
  double _viewW = 360;
  double _viewH = 600;

  final _vScroll = ScrollController();
  final _hScroll = ScrollController();
  final Map<String, TextEditingController> _ctrls = {};
  _LiveStroke? _live;
  PointerDeviceKind? _liveKind;
  final _liveTick = ValueNotifier<int>(0);

  // two-finger pinch: the view is scaled (cheap) while the fingers move, the pages are re-drawn once at the end
  final Map<int, Offset> _fingers = {};
  bool _pinching = false;
  double _pinchStartDist = 1;
  double _pinchBaseZoom = 1;
  Offset _pinchLastFocal = Offset.zero;
  final _pinchScale = ValueNotifier<double>(1);
  final _pinchOrigin = ValueNotifier<Offset>(Offset.zero);

  SignatureResult? _savedSig;

  bool _saving = false;
  String _savingText = '';

  @override
  void initState() {
    super.initState();
    _download();
    SignatureStore.load().then((r) {
      if (mounted) setState(() => _savedSig = r);
    });
  }

  @override
  void dispose() {
    _doc?.dispose();
    _vScroll.dispose();
    _hScroll.dispose();
    _liveTick.dispose();
    _pinchScale.dispose();
    _pinchOrigin.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ loading
  Future<void> _download() async {
    setState(() {
      _loadError = '';
      _downloadPct = 0;
    });
    try {
      final res = await Dio().get<List<int>>(
        s(widget.file['url']),
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 3)),
        onReceiveProgress: (got, total) {
          if (mounted && total > 0) setState(() => _downloadPct = got / total);
        },
      );
      final bytes = Uint8List.fromList(res.data ?? const []);
      final doc = await PdfDocument.openData(bytes, sourceName: 'sign-${DateTime.now().microsecondsSinceEpoch}');
      if (!mounted) {
        doc.dispose();
        return;
      }
      setState(() {
        _bytes = bytes;
        _doc = doc;
        _pageSizes = [for (final p in doc.pages) Size(p.width, p.height)];
        _downloadPct = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = 'មិនអាចផ្ទុកឯកសារ PDF បានទេ';
          _downloadPct = null;
        });
      }
    }
  }

  // ------------------------------------------------------------------ state helpers
  void _pushHistory() {
    _history.add(List<Ann>.of(_anns));
    if (_history.length > _historyMax) _history.removeAt(0);
  }

  void _commit(List<Ann> next) {
    _pushHistory();
    setState(() => _anns = next);
  }

  void _replace(Ann a) {
    setState(() => _anns = [for (final x in _anns) x.id == a.id ? a : x]);
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      _anns = _history.removeLast();
      if (_selectedId != null && !_anns.any((a) => a.id == _selectedId)) _selectedId = null;
    });
  }

  void _remove(String id) {
    _commit(_anns.where((a) => a.id != id).toList());
    if (_selectedId == id) _selectedId = null;
    _ctrls.remove(id)?.dispose();
  }

  Ann? get _selected {
    for (final a in _anns) {
      if (a.id == _selectedId) return a;
    }
    return null;
  }

  /// Text boxes left empty are dropped (the one being typed in is kept).
  void _pruneBlank({String? keep}) {
    final blanks = _anns.where((a) => a is TextAnn && a.blank && a.id != keep).map((a) => a.id).toSet();
    if (blanks.isEmpty) return;
    setState(() => _anns = _anns.where((a) => !blanks.contains(a.id)).toList());
    for (final id in blanks) {
      _ctrls.remove(id)?.dispose();
    }
  }

  void _select(String? id) {
    _pruneBlank(keep: id);
    setState(() {
      _selectedId = id;
      if (id != null) {
        final a = _selected;
        if (a is TextAnn) {
          _color = a.color;
          _fontPt = _nearest(_fontSizes, (a.size * basePageWidth).round());
        }
      }
    });
  }

  int _nearest(List<int> list, int v) =>
      list.reduce((a, b) => (a - v).abs() <= (b - v).abs() ? a : b);

  void _setTool(_Tool t) {
    if (t == _tool) return;
    _pruneBlank();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _tool = t;
      if (t == _Tool.pen) _selectedId = null;
    });
  }

  void _setColor(Color c) {
    final sel = _selected;
    setState(() => _color = c);
    if (sel != null) {
      _pushHistory();
      _replace(sel is TextAnn ? sel.copyWith(color: c) : (sel as DrawAnn).copyWith(color: c));
    }
  }

  void _setFont(int pt) {
    setState(() => _fontPt = pt);
    final sel = _selected;
    if (sel is TextAnn) {
      _pushHistory();
      _replace(sel.copyWith(size: pt / basePageWidth));
    }
  }

  TextEditingController _ctrlFor(TextAnn a) {
    final c = _ctrls.putIfAbsent(a.id, () => TextEditingController(text: a.text));
    if (c.text != a.text) {
      c.value = TextEditingValue(text: a.text, selection: TextSelection.collapsed(offset: a.text.length));
    }
    return c;
  }

  // ------------------------------------------------------------------ geometry
  double _pageWidth(double viewport) => math.max(120, (viewport - 24) * _zoom);

  double _pageHeight(int n, double pageW) {
    final sz = _pageSizes[n - 1];
    return pageW * sz.height / sz.width;
  }

  /// The page in the middle of the screen and the vertical fraction of that page.
  (int, double) _centerPage(double viewportW, double viewportH) {
    final w = _pageWidth(viewportW);
    final center = (_vScroll.hasClients ? _vScroll.offset : 0) + viewportH / 2;
    var top = _gap;
    for (var n = 1; n <= _pageSizes.length; n++) {
      final h = _pageHeight(n, w);
      if (center < top + h + _gap / 2 || n == _pageSizes.length) {
        return (n, clampD((center - top) / h, 0, 1));
      }
      top += h + _gap;
    }
    return (1, 0);
  }

  Ann? _byId(String id) {
    for (final a in _anns) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Move by a fraction of the page. Always starts from the CURRENT annotation, so several pointer
  /// events in one frame (stylus) are not lost.
  void _nudge(String id, double dx, double dy) {
    final cur = _byId(id);
    if (cur == null) return;
    final o = originOf(cur);
    _replace(cur.moved(cur.page, o.dx + dx, o.dy + dy));
  }

  // ------------------------------------------------------------------ zoom (pinch, two-finger pan, buttons)
  /// Scroll position -> "page units" (page number - 1 + fraction of that page's height), at page width [pageW].
  double _yToUnits(double y, double pageW) {
    var top = _gap;
    for (var n = 1; n <= _pageSizes.length; n++) {
      final h = _pageHeight(n, pageW);
      if (y < top + h + _gap || n == _pageSizes.length) return (n - 1) + (y - top) / h;
      top += h + _gap;
    }
    return 0;
  }

  double _unitsToY(double u, double pageW) {
    final n = u.floor().clamp(0, _pageSizes.length - 1);
    var top = _gap;
    for (var i = 1; i <= n; i++) {
      top += _pageHeight(i, pageW) + _gap;
    }
    return top + (u - n) * _pageHeight(n + 1, pageW);
  }

  double _contentW(double pageW) => math.max(_viewW, pageW + 24);

  double _pageLeft(double pageW) => 12 + (_contentW(pageW) - 24 - pageW) / 2;

  /// Change the zoom keeping the point under [focal] (screen position inside the viewer) where it is.
  void _applyZoom(double target, Offset focal) {
    final z = clampD(target, _zoomMin, _zoomMax);
    if ((z - _zoom).abs() < 0.002) {
      if (_pinching) setState(() => _pinching = false);
      return;
    }
    final oldW = _pageWidth(_viewW);
    final newW = math.max(120.0, (_viewW - 24) * z);
    final oldV = _vScroll.hasClients ? _vScroll.offset : 0.0;
    final oldH = _hScroll.hasClients ? _hScroll.offset : 0.0;

    final u = _yToUnits(oldV + focal.dy, oldW);
    final newV = math.max(0.0, _unitsToY(u, newW) - focal.dy);
    final frac = (oldH + focal.dx - _pageLeft(oldW)) / oldW;
    final newH = clampD(_pageLeft(newW) + frac * newW - focal.dx, 0, math.max(0, _contentW(newW) - _viewW));

    // set the new offsets BEFORE the pages are laid out at the new size: no jump on screen
    if (_vScroll.hasClients) _vScroll.position.correctBy(newV - _vScroll.offset);
    if (_hScroll.hasClients) _hScroll.position.correctBy(newH - _hScroll.offset);
    setState(() {
      _zoom = z;
      _pinching = false;
    });
    if (!_hScroll.hasClients && newH > 0) {
      // the sideways scroller only exists once the page is wider than the screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _hScroll.hasClients) _hScroll.jumpTo(math.min(newH, _hScroll.position.maxScrollExtent));
      });
    }
  }

  int? _pairA;
  int? _pairB;

  bool _isFinger(PointerEvent e) => e.kind != PointerDeviceKind.stylus && e.kind != PointerDeviceKind.invertedStylus;

  void _fingerDown(PointerDownEvent e) {
    if (!_isFinger(e) || _saving) return;
    // a stylus stroke is in progress: a resting palm must not start a pinch
    if (_live != null && _liveKind != null && _liveKind != PointerDeviceKind.touch) return;
    _fingers[e.pointer] = e.localPosition;
    if (_fingers.length == 2 && !_pinching) _startPinch();
  }

  void _startPinch() {
    final ids = _fingers.keys.take(2).toList();
    _pairA = ids[0];
    _pairB = ids[1];
    final a = _fingers[ids[0]]!;
    final b = _fingers[ids[1]]!;
    _pinchStartDist = math.max(24.0, (a - b).distance);
    _pinchBaseZoom = _zoom;
    _pinchLastFocal = (a + b) / 2;
    _pinchOrigin.value = _pinchLastFocal;
    _pinchScale.value = 1;
    if (_live != null) {
      _live = null; // drop the half-drawn stroke: this is a pinch, not a line
      _liveTick.value++;
    }
    setState(() => _pinching = true);
  }

  void _fingerMove(PointerMoveEvent e) {
    if (!_fingers.containsKey(e.pointer)) return;
    _fingers[e.pointer] = e.localPosition;
    if (!_pinching) return;
    final a = _fingers[_pairA];
    final b = _fingers[_pairB];
    if (a == null || b == null) return;
    final focal = (a + b) / 2;
    final d = focal - _pinchLastFocal;
    _pinchLastFocal = focal;
    // two fingers also scroll: the content follows the middle point of the fingers
    if (_vScroll.hasClients) {
      final p = _vScroll.position;
      p.jumpTo(clampD(p.pixels - d.dy, p.minScrollExtent, p.maxScrollExtent));
    }
    if (_hScroll.hasClients) {
      final p = _hScroll.position;
      p.jumpTo(clampD(p.pixels - d.dx, p.minScrollExtent, p.maxScrollExtent));
    }
    final raw = (a - b).distance / _pinchStartDist;
    _pinchScale.value = clampD(raw, _zoomMin / _pinchBaseZoom, _zoomMax / _pinchBaseZoom);
    _pinchOrigin.value = focal;
  }

  void _fingerUp(PointerEvent e) {
    final inPair = e.pointer == _pairA || e.pointer == _pairB;
    _fingers.remove(e.pointer);
    if (_pinching && inPair) {
      final sc = _pinchScale.value;
      final focal = _pinchOrigin.value;
      _pairA = null;
      _pairB = null;
      _pinchScale.value = 1;
      _applyZoom(_pinchBaseZoom * sc, focal);
    }
  }

  // ------------------------------------------------------------------ actions
  void _addText(int page, Offset local, Size pageSize) {
    _pruneBlank();
    final w = _defaultTextW;
    final x = clampD(local.dx / pageSize.width, 0, 1 - w);
    final y = clampD(local.dy / pageSize.height - 0.01, 0, 0.95);
    final a = TextAnn(
      id: newAnnId(),
      page: page,
      color: _color,
      x: x,
      y: y,
      w: w,
      text: '',
      size: _fontPt / basePageWidth,
    );
    _commit([..._anns, a]);
    setState(() {
      _selectedId = a.id;
      _focusId = a.id;
      _tool = _Tool.hand; // type now, then move or add more with the text tool
    });
  }

  /// Tap: place the signature kept on the phone at once. No saved one yet (or [fresh]): draw it first.
  Future<void> _addSignature({bool fresh = false}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    var r = fresh ? null : _savedSig;
    if (r == null) {
      r = await showSignaturePad(context, initialColor: _color);
      if (r == null || !mounted) return;
      if (r.remember) {
        SignatureStore.save(r);
        setState(() => _savedSig = r);
      }
    } else {
      HapticFeedback.selectionClick();
    }
    _placeSignature(r);
  }

  Future<void> _forgetSignature() async {
    if (_savedSig == null) return;
    final ok = await confirmDialog(
      context,
      title: 'លុបហត្ថលេខាដែលបានចងចាំ?',
      message: 'លើកក្រោយអ្នកនឹងត្រូវគូរហត្ថលេខាម្តងទៀត។',
      confirmText: 'លុប',
      danger: true,
    );
    if (!ok || !mounted) return;
    await SignatureStore.clear();
    if (mounted) setState(() => _savedSig = null);
  }

  void _placeSignature(SignatureResult r) {
    _pruneBlank();

    final (page, yCenter) = _centerPage(_viewW, _viewH);
    const width = 0.3; // of the page width
    final h = r.ratio * width;
    final sig = DrawAnn(
      id: newAnnId(),
      page: page,
      color: r.color,
      width: r.width * width,
      strokes: [
        for (final s in r.strokes) [for (final p in s) Offset(p.dx * width, p.dy * width)],
      ],
    ).moved(page, 0.35, clampD(yCenter - h / 2, 0, math.max(0, 1 - h)));
    _commit([..._anns, sig]);
    setState(() {
      _selectedId = sig.id;
      _tool = _Tool.hand;
    });
  }

  Future<void> _save() async {
    if (widget.blockedReason.isNotEmpty) {
      showSnack(context, widget.blockedReason, error: true);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _pruneBlank();
    if (_anns.isEmpty) {
      showSnack(context, 'មិនទាន់មានអ្វីត្រូវរក្សាទុកទេ');
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'រក្សាទុកឯកសារដែលបានចុះហត្ថលេខា?',
      message: 'ឯកសារដើមនឹងត្រូវជំនួសដោយឯកសារនេះ។ ទំព័រដែលមានការសរសេរនឹងក្លាយជារូបភាព។',
      confirmText: 'រក្សាទុក',
    );
    if (!ok || !mounted) return;

    setState(() {
      _saving = true;
      _savingText = 'កំពុងរៀបចំឯកសារ...';
    });
    try {
      final bytes = await exportSignedPdf(
        original: _bytes!,
        annotations: _anns,
        onProgress: (d, t) {
          if (mounted) setState(() => _savingText = 'កំពុងរៀបចំទំព័រ $d / $t');
        },
      );
      if (mounted) setState(() => _savingText = 'កំពុងរក្សាទុក...');
      final fresh = await widget.onSave(bytes, widget.file);
      if (!mounted) return;
      _anns = [];
      Navigator.pop(context, fresh);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, _errText(e), error: true);
      }
    }
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final name = s(widget.file['original_name']).isEmpty ? 'PDF' : s(widget.file['original_name']);
    return PopScope(
      canPop: _anns.isEmpty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        final leave = await confirmDialog(
          context,
          title: 'ចាកចេញដោយមិនរក្សាទុក?',
          message: 'អ្វីដែលអ្នកបានសរសេរនឹងបាត់បង់។',
          confirmText: 'ចាកចេញ',
          danger: true,
        );
        if (!context.mounted || !leave) return;
        setState(() => _anns = []);
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
          actions: [
            IconButton(
              tooltip: 'ត្រឡប់ក្រោយ',
              onPressed: _history.isEmpty || _saving ? null : _undo,
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: 'បង្រួម',
              onPressed: _zoom <= _zoomMin || _saving ? null : () => _applyZoom(_zoom - 0.25, Offset(_viewW / 2, _viewH / 2)),
              icon: const Icon(Icons.zoom_out),
            ),
            IconButton(
              tooltip: 'ពង្រីក',
              onPressed: _zoom >= _zoomMax || _saving ? null : () => _applyZoom(_zoom + 0.25, Offset(_viewW / 2, _viewH / 2)),
              icon: const Icon(Icons.zoom_in),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _saving || _doc == null ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('រក្សាទុក'),
              ),
            ),
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loadError.isNotEmpty) return ErrorState(_loadError, onRetry: _download);
    if (_doc == null) {
      return SkeletonPage(
        label: _downloadPct == null ? 'កំពុងផ្ទុក...' : 'កំពុងទាញយក ${(_downloadPct! * 100).round()}%',
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  _viewW = box.maxWidth;
                  _viewH = box.maxHeight;
                  final pageW = _pageWidth(box.maxWidth);
                  final locked = _lockScroll || _tool == _Tool.pen || _saving || _pinching;
                  final physics = locked ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics();
                  final contentW = math.max(box.maxWidth, pageW + 24);

                  Widget list = ListView.builder(
                    controller: _vScroll,
                    physics: physics,
                    padding: const EdgeInsets.fromLTRB(12, _gap, 12, 140),
                    itemCount: _pageSizes.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: _gap),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _page(i + 1, pageW),
                      ),
                    ),
                  );
                  if (contentW > box.maxWidth) {
                    list = SingleChildScrollView(
                      controller: _hScroll,
                      scrollDirection: Axis.horizontal,
                      physics: physics,
                      child: SizedBox(width: contentW, height: box.maxHeight, child: list),
                    );
                  }
                  // the view is only scaled while the fingers move (smooth); the pages are redrawn once at the end
                  final scaled = AnimatedBuilder(
                    animation: Listenable.merge([_pinchScale, _pinchOrigin]),
                    child: list,
                    builder: (_, child) {
                      final sc = _pinchScale.value;
                      if (sc == 1) return child!;
                      final o = _pinchOrigin.value;
                      return Transform(
                        transform: Matrix4.translationValues(o.dx, o.dy, 0)
                          ..multiply(Matrix4.diagonal3Values(sc, sc, 1))
                          ..multiply(Matrix4.translationValues(-o.dx, -o.dy, 0)),
                        child: child,
                      );
                    },
                  );
                  return Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: _fingerDown,
                    onPointerMove: _fingerMove,
                    onPointerUp: _fingerUp,
                    onPointerCancel: _fingerUp,
                    child: Container(color: const Color(0xFFE3E8E7), child: ClipRect(child: scaled)),
                  );
                },
              ),
            ),
            _toolbar(),
          ],
        ),
        if (_saving)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black45,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 200, child: SkeletonLines(lines: 2)),
                        const SizedBox(height: 16),
                        Text(_savingText),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------------ one page
  Widget _page(int n, double pageW) {
    final pageH = _pageHeight(n, pageW);
    final size = Size(pageW, pageH);
    final items = _anns.where((a) => a.page == n).toList();
    final draws = items.whereType<DrawAnn>().toList();
    final texts = items.whereType<TextAnn>().toList();

    return Container(
      width: pageW,
      height: pageH,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: PdfPageView(
              document: _doc,
              pageNumber: n,
              decoration: const BoxDecoration(color: Colors.white),
            ),
          ),
          Positioned.fill(child: _inputLayer(n, size)),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _liveTick,
                builder: (_, __) => CustomPaint(
                  painter: DrawLayerPainter(
                    draws,
                    live: _live != null && _live!.page == n ? _live!.points : null,
                    liveColor: _color,
                    liveWidth: _penPt / basePageWidth,
                  ),
                ),
              ),
            ),
          ),
          for (final d in draws) _drawBox(d, size),
          for (final t in texts) _textBox(t, size),
        ],
      ),
    );
  }

  Widget _inputLayer(int n, Size size) {
    switch (_tool) {
      case _Tool.text:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _addText(n, d.localPosition, size),
        );
      case _Tool.pen:
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            // another finger is already down: this is a pinch / two-finger scroll, not a line
            if (_isFinger(e) && _fingers.isNotEmpty) return;
            _live = _LiveStroke(n, [_frac(e.localPosition, size)]);
            _liveKind = e.kind;
            _liveTick.value++;
          },
          onPointerMove: (e) {
            final l = _live;
            if (l == null || l.page != n) return;
            final p = _frac(e.localPosition, size);
            // skip points closer than ~0.3 px: same line, far fewer points to draw and save
            final last = l.points.last;
            if ((p.dx - last.dx).abs() * size.width < 0.3 && (p.dy - last.dy).abs() * size.height < 0.3) return;
            l.points.add(p);
            _liveTick.value++;
          },
          onPointerUp: (e) => _endStroke(n),
          onPointerCancel: (e) => _endStroke(n),
        );
      case _Tool.hand:
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            _select(null);
          },
        );
    }
  }

  Offset _frac(Offset p, Size size) =>
      Offset(clampD(p.dx / size.width, 0, 1), clampD(p.dy / size.height, 0, 1));

  void _endStroke(int n) {
    final l = _live;
    _live = null;
    _liveKind = null;
    _liveTick.value++;
    if (l == null || l.points.isEmpty) return;
    _commit([
      ..._anns,
      DrawAnn(
        id: newAnnId(),
        page: l.page,
        color: _color,
        strokes: [l.points],
        width: _penPt / basePageWidth,
      ),
    ]);
  }

  // ------------------------------------------------------------------ text box
  static const double _barH = 34;

  Widget _textBox(TextAnn a, Size page) {
    final selected = a.id == _selectedId;
    final px = a.size * page.width;
    final barAbove = a.y > 0.8;
    final editable = _tool != _Tool.pen;

    final field = Container(
      key: ValueKey('field-${a.id}'),
      decoration: BoxDecoration(
        border: Border.all(color: selected ? AppColors.primary : Colors.transparent, width: 1.2),
        color: selected ? AppColors.primary.withValues(alpha: 0.05) : Colors.transparent,
      ),
      padding: EdgeInsets.symmetric(horizontal: px * textPadX, vertical: px * textPadY),
      child: IgnorePointer(
        ignoring: !editable,
        child: TextField(
          controller: _ctrlFor(a),
          autofocus: a.id == _focusId,
          maxLines: null,
          minLines: 1,
          keyboardType: TextInputType.multiline,
          style: annotationTextStyle(a, page.width),
          cursorColor: a.color,
          decoration: InputDecoration.collapsed(
            hintText: 'វាយអក្សរ…',
            hintStyle: annotationTextStyle(a, page.width).copyWith(color: AppColors.other),
          ),
          onTap: () => _select(a.id),
          onChanged: (v) {
            final cur = _byId(a.id);
            if (cur is TextAnn) _replace(cur.copyWith(text: v));
          },
        ),
      ),
    );

    final bar = _handleBar(
      key: ValueKey('bar-${a.id}'),
      onGripMove: (d) => _nudge(a.id, d.dx / page.width, d.dy / page.height),
      onGripStart: _beginDrag,
      onGripEnd: _endDrag,
      onDelete: () => _remove(a.id),
    );

    // the bar is part of the widget (above or below the text) so it can be touched inside the page
    final topSpace = selected && barAbove;
    return Positioned(
      left: a.x * page.width,
      top: a.y * page.height - (topSpace ? _barH : 0),
      width: a.w * page.width,
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (topSpace) bar,
              field,
              if (selected && !barAbove) bar,
            ],
          ),
          if (selected)
            Positioned(
              right: 0,
              top: topSpace ? _barH : 0,
              bottom: topSpace ? 0 : (_barH),
              width: 22,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _beginDrag(),
                onPointerMove: (e) {
                  final cur = _byId(a.id);
                  if (cur is TextAnn) {
                    _replace(cur.copyWith(w: clampD(cur.w + e.delta.dx / page.width, 0.1, 1 - cur.x)));
                  }
                },
                onPointerUp: (_) => _endDrag(),
                onPointerCancel: (_) => _endDrag(),
                child: const Center(child: Icon(Icons.drag_indicator, size: 18, color: AppColors.primary)),
              ),
            ),
        ],
      ),
    );
  }

  void _beginDrag() {
    _pushHistory();
    setState(() => _lockScroll = true);
  }

  void _endDrag() {
    if (_lockScroll) setState(() => _lockScroll = false);
  }

  Widget _handleBar({
    Key? key,
    required void Function(Offset delta) onGripMove,
    required VoidCallback onGripStart,
    required VoidCallback onGripEnd,
    required VoidCallback onDelete,
  }) {
    return Container(
      key: key,
      height: _barH,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(15)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => onGripStart(),
              onPointerMove: (e) => onGripMove(e.delta),
              onPointerUp: (_) => onGripEnd(),
              onPointerCancel: (_) => onGripEnd(),
              child: const SizedBox(
                width: 44,
                height: 30,
                child: Icon(Icons.open_with_rounded, size: 18, color: Colors.white),
              ),
            ),
            GestureDetector(
              onTap: onDelete,
              child: const SizedBox(
                width: 36,
                height: 30,
                child: Icon(Icons.delete_outline, size: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ drawing / signature box
  Widget _drawBox(DrawAnn a, Size page) {
    final selected = a.id == _selectedId;
    final b = a.bounds;
    final pad = math.max(8.0, a.width * page.width * 1.5);
    final left = b.left * page.width - pad;
    final top = b.top * page.height - pad;
    final w = math.max(b.width * page.width + pad * 2, 28.0);
    final h = math.max(b.height * page.height + pad * 2, 28.0);
    final barAbove = b.bottom > 0.8;
    final topSpace = selected && barAbove;
    final bottomSpace = selected && !barAbove;

    final bar = _handleBar(
      key: ValueKey('bar-${a.id}'),
      onGripStart: _beginDrag,
      onGripEnd: _endDrag,
      onGripMove: (d) => _nudge(a.id, d.dx / page.width, d.dy / page.height),
      onDelete: () => _remove(a.id),
    );
    final dragBody = selected && _tool == _Tool.hand;

    return Positioned(
      left: left,
      top: top - (topSpace ? _barH : 0),
      width: w,
      height: h + (topSpace || bottomSpace ? _barH : 0),
      child: Column(
        children: [
          if (topSpace) bar,
          SizedBox(
            key: ValueKey('frame-${a.id}'),
            width: w,
            height: h,
            child: Stack(
              children: [
                Positioned.fill(
                  // a selected signature can be dragged by itself (no need to find the move button)
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: dragBody ? (_) => _beginDrag() : null,
                    onPointerMove: dragBody ? (e) => _nudge(a.id, e.delta.dx / page.width, e.delta.dy / page.height) : null,
                    onPointerUp: dragBody ? (_) => _endDrag() : null,
                    onPointerCancel: dragBody ? (_) => _endDrag() : null,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _tool == _Tool.hand ? () => _select(a.id) : null,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: selected ? AppColors.primary : Colors.transparent, width: 1.2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => _beginDrag(),
                      onPointerMove: (e) {
                        final cur = _byId(a.id);
                        if (cur is! DrawAnn) return;
                        final cb = cur.bounds;
                        final curW = cb.width * page.width;
                        if (curW < 4) return;
                        final factor = ((curW + e.delta.dx) / curW).clamp(0.5, 2.0);
                        final next = cur.scaled(factor, cb.left, cb.top);
                        final nb = next.bounds; // keep it inside the page and not tiny
                        if (nb.right > 1 || nb.bottom > 1 || nb.width * page.width < 24) return;
                        _replace(next);
                      },
                      onPointerUp: (_) => _endDrag(),
                      onPointerCancel: (_) => _endDrag(),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.open_in_full_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (bottomSpace) bar,
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ toolbar
  Widget _toolbar() {
    final t = Theme.of(context).textTheme;
    final selText = _selected is TextAnn;
    final hint = switch (_tool) {
      _Tool.text => 'ចុចលើទំព័រដើម្បីដាក់អក្សរ',
      _Tool.pen => 'គូរដោយម្រាមមួយ · ម្រាមពីរដើម្បីពង្រីក ឬរមូល',
      _Tool.hand => _selected != null
          ? 'អូសដើម្បីផ្លាស់ទី · ចុចរង្វង់ជ្រុងដើម្បីប្តូរទំហំ'
          : (_savedSig != null ? 'ចុច "ហត្ថលេខា" ដើម្បីដាក់ភ្លាមៗ · ចុចយូរដើម្បីលុបហត្ថលេខាដែលបានចងចាំ' : 'ប្រើម្រាមពីរដើម្បីពង្រីក ឬរមូល'),
    };

    Widget toolButton(IconData icon, String label, bool on, VoidCallback onTap, {VoidCallback? onLongPress}) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _saving ? null : onTap,
          onLongPress: _saving ? null : onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: on ? AppColors.soft : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: on ? AppColors.primary : AppColors.muted),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: t.labelSmall?.copyWith(
                    color: on ? AppColors.primary : AppColors.muted,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hint.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(hint, style: t.bodySmall?.copyWith(color: AppColors.muted)),
                ),
              Row(
                children: [
                  toolButton(Icons.pan_tool_alt_outlined, 'ជ្រើស', _tool == _Tool.hand, () => _setTool(_Tool.hand)),
                  toolButton(Icons.text_fields_rounded, 'អក្សរ', _tool == _Tool.text, () => _setTool(_Tool.text)),
                  toolButton(Icons.edit_outlined, 'ប៊ិច', _tool == _Tool.pen, () => _setTool(_Tool.pen)),
                  toolButton(Icons.draw_outlined, 'ហត្ថលេខា', false, _addSignature, onLongPress: _savedSig == null ? null : _forgetSignature),
                  if (_savedSig != null) toolButton(Icons.gesture, 'គូរថ្មី', false, () => _addSignature(fresh: true)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final c in _colors)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _setColor(c),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(color: c == _color ? AppColors.primary : Colors.transparent, width: 3),
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (_tool == _Tool.pen)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final r = await showSelectSheet(
                          context,
                          title: 'កម្រាស់ប៊ិច',
                          options: [for (final w in _penWidths) Option('$w', '$w')],
                          selected: '$_penPt',
                          allowClear: false,
                        );
                        if (r != null && r.isNotEmpty) setState(() => _penPt = int.parse(r));
                      },
                      icon: const Icon(Icons.line_weight, size: 18),
                      label: Text('$_penPt'),
                    )
                  else if (_tool == _Tool.text || selText)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final r = await showSelectSheet(
                          context,
                          title: 'ទំហំអក្សរ',
                          options: [for (final f in _fontSizes) Option('$f', '$f')],
                          selected: '$_fontPt',
                          allowClear: false,
                        );
                        if (r != null && r.isNotEmpty) _setFont(int.parse(r));
                      },
                      icon: const Icon(Icons.format_size, size: 18),
                      label: Text('$_fontPt'),
                    ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<double>(
                    valueListenable: _pinchScale,
                    builder: (_, sc, __) => Text(
                      '${(_zoom * sc * 100).round()}%',
                      style: t.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
