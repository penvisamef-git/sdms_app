import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import 'annotation_painter.dart';
import 'annotations.dart';

class _JpegJob {
  _JpegJob(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}

Uint8List _encodeJpeg(_JpegJob j) {
  final image = img.Image.fromBytes(
    width: j.width,
    height: j.height,
    bytes: j.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 88));
}

/// Burn the annotations into a copy of the PDF.
///
/// Pages without annotations are copied untouched (text stays selectable). Every annotated page is
/// rendered together with its annotations into a high resolution image and put back in the same place,
/// so Khmer text keeps the phone's own fonts.
Future<Uint8List> exportSignedPdf({
  required Uint8List original,
  required List<Ann> annotations,
  void Function(int done, int total)? onProgress,
}) async {
  final src = await PdfDocument.openData(original, sourceName: 'original-${DateTime.now().microsecondsSinceEpoch}');
  final helpers = <PdfDocument>[];
  try {
    final byPage = <int, List<Ann>>{};
    for (final a in annotations) {
      byPage.putIfAbsent(a.page, () => []).add(a);
    }

    final replaced = <int, PdfPage>{};
    var done = 0;
    for (final entry in byPage.entries) {
      final n = entry.key;
      if (n < 1 || n > src.pages.length) continue;
      final page = src.pages[n - 1];

      // ~2000 px wide (about 240 dpi on A4), never more than 2600 px on a side
      var scale = 2000 / page.width;
      if (page.height * scale > 2600) scale = 2600 / page.height;
      final w = (page.width * scale).round();
      final h = (page.height * scale).round();

      final rendered = await page.render(
        fullWidth: w.toDouble(),
        fullHeight: h.toDouble(),
        width: w,
        height: h,
        backgroundColor: 0xFFFFFFFF,
      );
      if (rendered == null) throw Exception('មិនអាចបង្កើតទំព័រ $n បានទេ');
      final base = await rendered.createImage();
      rendered.dispose();

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImage(base, ui.Offset.zero, ui.Paint());
      final size = ui.Size(w.toDouble(), h.toDouble());
      for (final a in entry.value) {
        if (a is DrawAnn) paintDraw(canvas, size, a);
        if (a is TextAnn) paintText(canvas, size, a);
      }
      final merged = await recorder.endRecording().toImage(w, h);
      final data = await merged.toByteData(format: ui.ImageByteFormat.rawRgba);
      base.dispose();
      merged.dispose();
      if (data == null) throw Exception('មិនអាចបង្កើតរូបភាពបានទេ');

      final jpeg = await compute(
        _encodeJpeg,
        _JpegJob(data.buffer.asUint8List(), w, h),
      );
      final helper = await PdfDocument.createFromJpegData(
        jpeg,
        width: page.width,
        height: page.height,
        sourceName: 'signed-page-$n-${DateTime.now().microsecondsSinceEpoch}',
      );
      helpers.add(helper);
      replaced[n] = helper.pages.first;

      done++;
      onProgress?.call(done, byPage.length);
    }

    src.pages = [
      for (var i = 0; i < src.pages.length; i++) replaced[i + 1] ?? src.pages[i],
    ];
    await src.assemble();
    return await src.encodePdf();
  } finally {
    for (final d in helpers) {
      d.dispose();
    }
    src.dispose();
  }
}
