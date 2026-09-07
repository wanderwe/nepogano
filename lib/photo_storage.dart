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
///
/// Обмежений розмір — раніше карта росла необмежено на весь час життя
/// процесу, по одному запису на кожне переглянуте фото; довга прокрутка
/// Історії за багато місяців тримала б усі ці декодовані байти в пам'яті
/// назавжди. 120 — з запасом на кілька місяців перегляду за одну сесію.
const _photoCacheCap = 120;
final Map<String, Uint8List> _photoCache = {};

void _rememberInCache(String path, Uint8List bytes) {
  _photoCache.remove(path);
  _photoCache[path] = bytes;
  while (_photoCache.length > _photoCacheCap) {
    _photoCache.remove(_photoCache.keys.first);
  }
}

Future<Uint8List?> downloadCheckinPhoto(String path, {int retries = 3}) async {
  final cached = _photoCache[path];
  if (cached != null) {
    // Освіжаємо позицію в LRU-порядку й на ПОПАДАННІ в кеш, не лише при
    // записі — інакше фото, яке юзер активно й повторно переглядає,
    // могло б витіснитись лише через вік вставки, попри те, що воно
    // явно ще "гаряче".
    _rememberInCache(path, cached);
    return cached;
  }

  // Той самий клас короткочасних мережевих похибок, що й для решти запитів
  // Supabase (SocketException одразу після старту застосунку) — тут теж
  // ретраїмо, бо storage.download() не проходить через наш загальний
  // RetryClient.
  for (var attempt = 0; attempt <= retries; attempt++) {
    try {
      final bytes = await Supabase.instance.client.storage.from(_bucket).download(path);
      _rememberInCache(path, bytes);
      return bytes;
    } catch (e) {
      if (attempt == retries) return null;
      await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
    }
  }
  return null;
}

Future<void> deleteCheckinPhoto(String path) async {
  try {
    await Supabase.instance.client.storage.from(_bucket).remove([path]);
  } catch (_) {
    // Викликається fire-and-forget (unawaited) з _save() — транзиентна
    // мережева помилка тут не має вилітати необробленим винятком. Гірший
    // наслідок — старий файл лишається в сховищі осиротілим, не крах.
  }
  _photoCache.remove(path);
}
