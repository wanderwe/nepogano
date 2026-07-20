import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

const _bucket = 'checkin-photos';

/// Стискає і завантажує фото чек-іну в приватний бакет, повертає шлях
/// (не публічний URL — доступ через [downloadCheckinPhoto], бо бакет
/// приватний і керується RLS-політиками сховища).
Future<String> uploadCheckinPhoto(File file) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser!.id;
  final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';

  await supabase.storage.from(_bucket).upload(
        path,
        file,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );

  return path;
}

/// Локальний кеш у пам'яті на сесію — те саме фото не тягнеться з мережі
/// повторно при кожному перебудуванні екрана.
final Map<String, Uint8List> _photoCache = {};

Future<Uint8List?> downloadCheckinPhoto(String path) async {
  final cached = _photoCache[path];
  if (cached != null) return cached;

  try {
    final bytes = await Supabase.instance.client.storage.from(_bucket).download(path);
    _photoCache[path] = bytes;
    return bytes;
  } catch (e) {
    return null;
  }
}

Future<void> deleteCheckinPhoto(String path) async {
  await Supabase.instance.client.storage.from(_bucket).remove([path]);
  _photoCache.remove(path);
}
