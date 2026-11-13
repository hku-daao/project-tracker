import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_msg_parser/flutter_msg_parser.dart';

import '../../utils/picked_file_bytes.dart';

/// Text pulled from one dropped file for the POC bibliography.
class PocFileText {
  const PocFileText({
    required this.name,
    required this.text,
    this.unreadReason,
  });

  final String name;
  final String text;
  final String? unreadReason;

  bool get readable => text.trim().isNotEmpty;
}

class PocFileTextReader {
  static const int _perFileChars = 40000;

  static PocFileText read(PickedFileBytes file) {
    final name = file.name.trim().isEmpty ? 'file' : file.name.trim();
    final ext = _extension(name);
    try {
      final raw = switch (ext) {
        'msg' => _readMsg(file.bytes),
        'docx' => _readDocx(file.bytes),
        'html' || 'htm' => _plainFromHtml(_decodeText(file.bytes)),
        'txt' ||
        'md' ||
        'csv' ||
        'json' ||
        'xml' ||
        'eml' ||
        'log' ||
        'rtf' => _decodeText(file.bytes),
        _ => _decodeText(file.bytes),
      };
      final text = raw.trim();
      if (text.isEmpty) {
        return PocFileText(
          name: name,
          text: '',
          unreadReason: 'No readable text in this file.',
        );
      }
      if (text.length > _perFileChars) {
        return PocFileText(
          name: name,
          text: '${text.substring(0, _perFileChars)}\n[truncated]',
        );
      }
      return PocFileText(name: name, text: text);
    } catch (e) {
      return PocFileText(
        name: name,
        text: '',
        unreadReason: 'Could not read this file.',
      );
    }
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static String _readMsg(List<int> bytes) {
    final parsed = parseMsg(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    final body = (parsed.text ?? '').trim().isNotEmpty
        ? parsed.text!.trim()
        : _plainFromHtml(parsed.html ?? '');
    final to = (parsed.recipients ?? const <MsgEmailAddress>[])
        .map((r) {
          final name = r.name.trim();
          final email = r.email.trim();
          if (name.isEmpty) return email;
          if (email.isEmpty) return name;
          return '$name <$email>';
        })
        .where((line) => line.isNotEmpty)
        .join('; ');
    final subject = parsed.subject.trim();
    final from = (parsed.from ?? '').trim();
    return [
      if (subject.isNotEmpty) 'Subject: $subject',
      if (from.isNotEmpty) 'From: $from',
      if (to.isNotEmpty) 'To: $to',
      if (body.isNotEmpty) body,
    ].join('\n');
  }

  static String _readDocx(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? doc;
    for (final file in archive.files) {
      if (file.name == 'word/document.xml') {
        doc = file;
        break;
      }
    }
    if (doc == null) return '';
    final xml = utf8.decode(doc.content, allowMalformed: true);
    final matches = RegExp(
      r'<w:t[^>]*>(.*?)</w:t>',
      dotAll: true,
    ).allMatches(xml);
    return matches
        .map((m) => _decodeXml(m.group(1) ?? ''))
        .where((part) => part.isNotEmpty)
        .join(' ');
  }

  static String _decodeText(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static String _plainFromHtml(String html) {
    return _decodeXml(html.replaceAll(RegExp(r'<[^>]+>'), ' '))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _decodeXml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }
}
