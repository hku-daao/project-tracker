import 'dart:convert';
import 'dart:html' as html;

class AsanaFilterCookieStorage {
  static const int _maxAgeSeconds = 60 * 60 * 24 * 180;

  static Map<String, dynamic>? load(String key) {
    final encoded = _readCookie(key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = utf8.decode(base64Url.decode(encoded));
      final value = jsonDecode(decoded);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  static void save(String key, Map<String, dynamic> value) {
    final json = jsonEncode(value);
    final encoded = base64Url.encode(utf8.encode(json));
    html.document.cookie = [
      '$key=$encoded',
      'path=/',
      'max-age=$_maxAgeSeconds',
      'SameSite=Lax',
    ].join('; ');
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
