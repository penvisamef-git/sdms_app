import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/cloudinary_upload.dart';
import 'common.dart';

/// Biggest file the API accepts (same as the web).
const maxFileMb = 20;
const maxFiles = 30;

/// Choose files from the phone (files, gallery, camera) and list the ones chosen.
class FilePickerField extends StatelessWidget {
  const FilePickerField({
    super.key,
    required this.files,
    required this.onChanged,
    this.disabled = false,
    this.hint,
  });

  final List<LocalFile> files;
  final ValueChanged<List<LocalFile>> onChanged;
  final bool disabled;
  final String? hint;

  void _add(BuildContext context, Iterable<LocalFile> picked) {
    final next = [...files];
    for (final f in picked) {
      if (f.size > maxFileMb * 1024 * 1024) {
        showSnack(context, '"${f.name}" ធំពេក! (អតិបរមា $maxFileMb MB)', error: true);
        continue;
      }
      if (next.any((e) => e.path == f.path)) continue;
      next.add(f);
    }
    onChanged(next);
  }

  Future<void> _pickFiles(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(); // empty list when cancelled
      if (picked.isEmpty || !context.mounted) return;
      final out = <LocalFile>[];
      for (final f in picked) {
        final path = f.path;
        if (path == null) continue;
        out.add(LocalFile(path: path, name: f.name, size: (await f.length()) ?? await File(path).length()));
      }
      if (context.mounted) _add(context, out);
    } catch (_) {
      if (context.mounted) showSnack(context, 'មិនអាចជ្រើសរើសឯកសារបានទេ', error: true);
    }
  }

  Future<void> _pickImages(BuildContext context, ImageSource source) async {
    try {
      final picker = ImagePicker();
      final list = source == ImageSource.camera
          ? [if (await picker.pickImage(source: source, imageQuality: 90) case final x?) x]
          : await picker.pickMultiImage(imageQuality: 90);
      if (list.isEmpty || !context.mounted) return;
      final out = <LocalFile>[];
      for (final x in list) {
        out.add(LocalFile(path: x.path, name: x.name, size: await x.length()));
      }
      if (context.mounted) _add(context, out);
    } catch (_) {
      if (context.mounted) showSnack(context, 'មិនអាចបើករូបភាពបានទេ', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < files.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.attach_file, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(files[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(formatBytes(files[i].size), style: t.bodySmall?.copyWith(color: AppColors.muted)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: disabled ? null : () => onChanged([...files]..removeAt(i)),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: disabled ? null : () => _pickFiles(context),
              icon: const Icon(Icons.upload_file),
              label: const Text('ជ្រើសឯកសារ'),
            ),
            OutlinedButton.icon(
              onPressed: disabled ? null : () => _pickImages(context, ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('រូបភាព'),
            ),
            OutlinedButton.icon(
              onPressed: disabled ? null : () => _pickImages(context, ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('ថតរូប'),
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint!, style: t.bodySmall?.copyWith(color: AppColors.muted)),
        ],
      ],
    );
  }
}
