import 'dart:convert';
import 'dart:html' as html;

class AsanaFilterCookieStorage {
  static const int _maxAgeSeconds = 60 * 60 * 24 * 180;

  /// Stay under the browser's per-cookie size limit once the name and
  /// attributes are included.
  static const int _chunkChars = 2800;

  static Map<String, dynamic>? load(String key) {
    final safe = _safeName(key);
    final fromSafe = _loadNamed(safe);
    if (fromSafe != null) return fromSafe;
    if (safe == key) return null;
    return _loadNamed(key);
  }

  static void save(String key, Map<String, dynamic> value) {
    final safe = _safeName(key);
    final encoded = base64Url.encode(utf8.encode(jsonEncode(value)));
    final previous = int.tryParse(_readCookie('${safe}__n') ?? '') ?? 0;
    if (encoded.length <= _chunkChars) {
      _write(safe, encoded);
      _expire('${safe}__n');
      for (var i = 0; i < previous; i++) {
        _expire('$safe$i');
      }
      if (safe != key) _expire(key);
      return;
    }
    final count = (encoded.length / _chunkChars).ceil();
    _expire(safe);
    for (var i = 0; i < count; i++) {
      final start = i * _chunkChars;
      final end = start + _chunkChars;
      _write(
        '$safe$i',
        encoded.substring(start, end > encoded.length ? encoded.length : end),
      );
    }
    _write('${safe}__n', '$count');
    for (var i = count; i < previous; i++) {
      _expire('$safe$i');
    }
    if (safe != key) _expire(key);
  }

  static Map<String, dynamic>? _loadNamed(String name) {
    final count = int.tryParse(_readCookie('${name}__n') ?? '') ?? 0;
    String? encoded;
    if (count > 0) {
      final parts = <String>[];
      for (var i = 0; i < count; i++) {
        final part = _readCookie('$name$i');
        if (part == null || part.isEmpty) return null;
        parts.add(part);
      }
      encoded = parts.join();
    } else {
      encoded = _readCookie(name);
    }
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = utf8.decode(base64Url.decode(encoded));
      final value = jsonDecode(decoded);
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Cookie names cannot contain `@`, which appears in a staff email.
  static String _safeName(String key) {
    final buffer = StringBuffer();
    for (final unit in key.codeUnits) {
      final letter =
          (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
      final digit = unit >= 0x30 && unit <= 0x39;
      if (letter || digit || unit == 0x5F || unit == 0x2D || unit == 0x2E) {
        buffer.writeCharCode(unit);
      } else if (unit == 0x40) {
        buffer.write('_at_');
      } else {
        buffer.write('_');
      }
    }
    return buffer.toString();
  }

  static void _write(String name, String value) {
    html.document.cookie = [
      '$name=$value',
      'path=/',
      'max-age=$_maxAgeSeconds',
      'SameSite=Lax',
    ].join('; ');
  }

  static void _expire(String name) {
    html.document.cookie = '$name=; path=/; max-age=0; SameSite=Lax';
  }

  static String? _readCookie(String key) {
    final cookie = html.document.cookie;
    if (cookie == null || cookie.isEmpty) return null;
    final prefix = '$key=';
    for (final part in cookie.split(';')) {
      final trimmed = part.trim();
      if (trimmed.startsWith(prefix)) {
        return trimmed.substring(prefix.length);
      }
    }
    return null;
  }
}
