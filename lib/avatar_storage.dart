import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

const _bucket = 'avatars';

/// Шлях завжди {user_id}/avatar.jpg — на відміну від фото чек-інів,
/// аватарка не має історії: заміна перезаписує той самий файл (upsert),
/// не створює новий об'єкт щоразу.
String _avatarPathFor(String userId) => '$userId/avatar.jpg';

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
  return path;
}

final Map<String, Uint8List> _avatarCache = {};

Future<Uint8List?> downloadAvatar(String path) async {
  final cached = _avatarCache[path];
  if (cached != null) return cached;
  try {
    final bytes = await Supabase.instance.client.storage
        .from(_bucket)
        .download(path);
    _avatarCache[path] = bytes;
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
