import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

const _imageExt = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic'];

String fileExtension(Json f) {
  final fmt = s(f['format']).toLowerCase();
  if (fmt.isNotEmpty) return fmt;
  final src = (s(f['original_name']).isNotEmpty ? s(f['original_name']) : s(f['url'])).split('?').first;
  final dot = src.lastIndexOf('.');
  return dot > 0 ? src.substring(dot + 1).toLowerCase() : '';
}

/// Opens one document file inside the app: PDF (pdfrx), image (zoom), anything else in the system viewer.
class FileViewerPage extends StatelessWidget {
  const FileViewerPage({super.key, required this.file});

  final Json file;

  Future<void> _external(BuildContext context) async {
    final ok = await launchUrl(Uri.parse(s(file['url'])), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showSnack(context, 'មិនអាចបើកឯកសារបានទេ', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final url = s(file['url']);
    final ext = fileExtension(file);
    final isPdf = ext == 'pdf';
    final isImage = _imageExt.contains(ext) || s(file['resource_type']) == 'image';
    final name = s(file['original_name']).isNotEmpty ? s(file['original_name']) : s(file['public_id']);

    Widget body;
    if (url.isEmpty) {
      body = const EmptyState('រកមិនឃើញឯកសារ', icon: Icons.error_outline);
    } else if (isPdf) {
      body = PdfViewer.uri(
        Uri.parse(url),
        params: PdfViewerParams(
          backgroundColor: const Color(0xFFE8ECEB),
          errorBannerBuilder: (context, error, stackTrace, documentRef) => ErrorState(
            'មិនអាចបើក PDF បានទេ',
            onRetry: () => _external(context),
          ),
        ),
      );
    } else if (isImage) {
      body = InteractiveViewer(
        minScale: 0.8,
        maxScale: 6,
        child: Center(
          child: Image.network(
            url,
            loadingBuilder: (_, child, p) => p == null ? child : const Center(child: CircularProgressIndicator()),
            errorBuilder: (_, __, ___) => const ErrorState('មិនអាចបង្ហាញរូបភាពបានទេ'),
          ),
        ),
      );
    } else {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 56, color: AppColors.muted),
            const SizedBox(height: 12),
            const Text('ប្រភេទឯកសារនេះមិនអាចបង្ហាញក្នុងកម្មវិធីបានទេ'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _external(context),
              icon: const Icon(Icons.open_in_new),
              label: const Text('បើកឯកសារ'),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name.isEmpty ? 'ឯកសារ' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
            Text(
              [ext.toUpperCase(), formatBytes(file['bytes'])].where((e) => e.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'បើកក្នុងកម្មវិធីផ្សេង',
            icon: const Icon(Icons.open_in_new),
            onPressed: url.isEmpty ? null : () => _external(context),
          ),
        ],
      ),
      body: body,
    );
  }
}
