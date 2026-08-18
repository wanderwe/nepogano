import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _bucket = 'avatars';

/// Шлях завжди {user_id}/avatar.jpg — на відміну від фото чек-інів,
/// аватарка не має історії: заміна перезаписує той самий файл (upsert),
/// не створює новий об'єкт щоразу.
String _avatarPathFor(String userId) => '$userId/avatar.jpg';

/// Файл диску, куди кешується завантажена аватарка — на відміну від
/// [_avatarCache] (лише пам'ять процесу), переживає холодний старт
/// застосунку, тому фото більше не "підвантажується з нуля" щоразу.
Future<File> _diskCacheFile(String path) async {
  final dir = await getApplicationSupportDirectory();
  final safeName = path.replaceAll('/', '_');
  return File('${dir.path}/avatar_cache_$safeName');
}

Future<String> uploadAvatar(File file) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser!.id;
  final path = _avatarPathFor(userId);

  await supabase.storage
      .from(_bucket)
      .upload(
        path,
        file,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );

  _avatarCache.remove(path);
  try {
    final cacheFile = await _diskCacheFile(path);
    if (cacheFile.existsSync()) await cacheFile.delete();
  } catch (_) {
    // Диск-кеш — лише прискорення, відсутність файлу для видалення не біда.
  }
  return path;
}

/// Прибирає файл із бакета й обидва кеші (пам'ять + диск) — той самий шлях
/// {user_id}/avatar.jpg, що й [uploadAvatar], тому не потребує аргументу.
Future<void> deleteAvatar() async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser!.id;
  final path = _avatarPathFor(userId);

  await supabase.storage.from(_bucket).remove([path]);

  _avatarCache.remove(path);
  try {
    final cacheFile = await _diskCacheFile(path);
    if (cacheFile.existsSync()) await cacheFile.delete();
  } catch (_) {
    // Диск-кеш — лише прискорення, відсутність файлу для видалення не біда.
  }
}

final Map<String, Uint8List> _avatarCache = {};

Future<Uint8List?> downloadAvatar(String path) async {
  final cached = _avatarCache[path];
  if (cached != null) return cached;

  try {
    final cacheFile = await _diskCacheFile(path);
    if (cacheFile.existsSync()) {
      final bytes = await cacheFile.readAsBytes();
      _avatarCache[path] = bytes;
      return bytes;
    }
  } catch (_) {
    // Читання диск-кешу впало — просто йдемо в мережу нижче.
  }

  try {
    final bytes = await Supabase.instance.client.storage
        .from(_bucket)
        .download(path);
    _avatarCache[path] = bytes;
    try {
      final cacheFile = await _diskCacheFile(path);
      await cacheFile.writeAsBytes(bytes);
    } catch (_) {
      // Диск-кеш — лише прискорення, помилка запису не критична.
    }
    return bytes;
  } catch (_) {
    return null;
  }
}

/// Паралельно (не по черзі) — щоб список друзів не чекав на кожну
/// аватарку послідовно; Storage не має batch-ендпоінту для кількох
/// об'єктів одразу, тож це найкраще практичне наближення.
Future<Map<String, Uint8List>> downloadAvatars(Iterable<String> paths) async {
  final uniquePaths = paths.toSet();
  final results = await Future.wait(
    uniquePaths.map((path) async {
      final bytes = await downloadAvatar(path);
      return MapEntry(path, bytes);
    }),
  );
  return {
    for (final entry in results)
      if (entry.value != null) entry.key: entry.value!,
  };
}
