import 'dart:io';

import 'package:dio/dio.dart';

import '../core/json.dart';
import 'api_client.dart';
import 'services.dart';

/// A file chosen on the phone, waiting to be uploaded.
class LocalFile {
  LocalFile({required this.path, required this.name, required this.size});

  final String path;
  final String name;
  final int size;
}

String? _extOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(dot + 1).toLowerCase() : null;
}

/// Uploads files straight to Cloudinary with a signature from the API
/// (no file goes through Vercel, so there is no 4.5 MB limit).
/// Returns the info the API saves: { url, public_id, resource_type, format, bytes, original_name }.
/// [onProgress] gets 0..1 for all files together.
Future<List<Json>> uploadToCloudinary(
  Api api,
  List<LocalFile> files,
  String folder, {
  void Function(double fraction)? onProgress,
}) async {
  if (files.isEmpty) return [];

  final res = await api.uploadSignature(folder);
  final sign = asObj(res['data']);
  final uploadUrl = s(sign['upload_url']);
  if (s(sign['signature']).isEmpty || uploadUrl.isEmpty) {
    throw ApiException('មិនអាចរៀបចំការ upload បានទេ');
  }

  final total = files.fold<int>(0, (sum, f) => sum + f.size);
  final done = List<int>.filled(files.length, 0);
  void report() {
    if (onProgress == null || total == 0) return;
    onProgress((done.fold<int>(0, (a, b) => a + b) / total).clamp(0.0, 1.0));
  }

  // plain Dio: this request goes to Cloudinary, not to our API
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(minutes: 10),
    receiveTimeout: const Duration(minutes: 2),
    validateStatus: (_) => true,
  ));

  final out = List<Json>.filled(files.length, <String, dynamic>{});
  for (var i = 0; i < files.length; i++) {
    final f = files[i];
    if (!await File(f.path).exists()) {
      throw ApiException('រកមិនឃើញឯកសារ "${f.name}" ក្នុងទូរស័ព្ទ');
    }
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(f.path, filename: f.name),
      'api_key': s(sign['api_key']),
      'timestamp': s(sign['timestamp']),
      'signature': s(sign['signature']),
      'folder': s(sign['folder']),
    });

    Response<dynamic> r;
    try {
      r = await dio.post<dynamic>(
        uploadUrl,
        data: form,
        onSendProgress: (sent, _) {
          done[i] = sent;
          report();
        },
      );
    } on DioException {
      throw ApiException('មិនអាច upload ទៅ Cloudinary បានទេ សូមពិនិត្យអ៊ីនធឺណិត');
    }

    final body = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
    if ((r.statusCode ?? 0) < 200 || (r.statusCode ?? 0) >= 300 || s(body['public_id']).isEmpty) {
      final msg = s(asObj(body['error'])['message']);
      throw ApiException(msg.isNotEmpty ? msg : 'Upload មិនបានសម្រេច (${r.statusCode})');
    }

    done[i] = f.size;
    report();
    out[i] = {
      'url': body['secure_url'],
      'public_id': body['public_id'],
      'resource_type': body['resource_type'],
      'format': body['format'] ?? _extOf(f.name),
      'bytes': body['bytes'],
      'original_name': f.name,
    };
  }
  return out;
}
