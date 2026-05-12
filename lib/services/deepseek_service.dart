import 'dart:convert';

import 'package:http/http.dart' as http;

/// OpenAI-compatible DeepSeek chat API.
///
/// Pass at build time: `--dart-define=DEEPSEEK_API_KEY=sk-...`
/// Optional: `--dart-define=DEEPSEEK_MODEL=deepseek-chat`
class DeepseekService {
  DeepseekService._();

  static const String _url =
      'https://api.deepseek.com/v1/chat/completions';

  static const String apiKey = String.fromEnvironment(
    'DEEPSEEK_API_KEY',
    defaultValue: '',
  );

  static const String model = String.fromEnvironment(
    'DEEPSEEK_MODEL',
    defaultValue: 'deepseek-chat',
  );

  static bool get isConfigured => apiKey.trim().isNotEmpty;

  /// Asks the model for a short title and longer description (JSON).
  static Future<({String title, String description})> suggestTitleDescription({
    required String userPrompt,
    String? extraContext,
  }) async {
    if (!isConfigured) {
      throw StateError(
        'Missing DEEPSEEK_API_KEY. Rebuild with '
        '--dart-define=DEEPSEEK_API_KEY=your_key',
      );
    }
    final trimmed = userPrompt.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Prompt is empty');
    }

    final ctx = extraContext?.trim();
    final system = StringBuffer()
      ..writeln(
        'You draft items for a workplace project tracker. '
        'Reply with ONLY a single JSON object (no markdown, no code fences): '
        '{"title":"...","description":"..."}. '
        'title: one short line. description: plain text for assignees; may use newlines.',
      );
    if (ctx != null && ctx.isNotEmpty) {
      system.writeln('Context:\n$ctx');
    }

    final body = jsonEncode({
      'model': model.trim().isEmpty ? 'deepseek-chat' : model.trim(),
      'messages': [
        {'role': 'system', 'content': system.toString()},
        {'role': 'user', 'content': trimmed},
      ],
      'temperature': 0.35,
    });

    final res = await http
        .post(
          Uri.parse(_url),
          headers: {
            'Authorization': 'Bearer ${apiKey.trim()}',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 120));

    if (res.statusCode != 200) {
      String detail = res.body;
      try {
        final m = jsonDecode(res.body);
        if (m is Map && m['error'] is Map) {
          final err = m['error'] as Map;
          detail = '${err['type'] ?? 'error'}: ${err['message'] ?? res.body}';
        }
      } catch (_) {}
      throw DeepseekHttpException(
        'DeepSeek HTTP ${res.statusCode}',
        detail.isNotEmpty ? detail : null,
      );
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected API response shape');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('No choices in API response');
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      throw const FormatException('Invalid choice object');
    }
    final message = first['message'];
    if (message is! Map<String, dynamic>) {
      throw const FormatException('Invalid message object');
    }
    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('Empty model content');
    }

    final parsed = _parseTitleDescriptionJson(content);
    if (parsed == null) {
      throw FormatException(
        'Could not parse JSON from model. Raw (truncated): '
        '${content.length > 400 ? content.substring(0, 400) : content}',
      );
    }
    return parsed;
  }

  static ({String title, String description})? _parseTitleDescriptionJson(
    String raw,
  ) {
    final map = _parseJsonObject(raw);
    if (map == null) return null;
    final t = map['title'];
    final d = map['description'];
    if (t is! String || d is! String) return null;
    return (title: t.trim(), description: d.trim());
  }

  static Map<String, dynamic>? _parseJsonObject(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      final lines = s.split('\n');
      if (lines.length > 2) {
        s = lines.sublist(1, lines.length - 1).join('\n').trim();
      }
    }
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    final i = s.indexOf('{');
    final j = s.lastIndexOf('}');
    if (i >= 0 && j > i) {
      try {
        final decoded = jsonDecode(s.substring(i, j + 1));
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }
}

class DeepseekHttpException implements Exception {
  DeepseekHttpException(this.message, [this.detail]);

  final String message;
  final String? detail;

  @override
  String toString() =>
      detail == null ? message : '$message\n$detail';
}
