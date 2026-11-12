import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One misspelled token in a title, description, comment, or discussion text.
class SpellMiss {
  const SpellMiss(this.start, this.end, this.word);

  final int start;
  final int end;
  final String word;
}

/// English spelling check that stays in the browser.
///
/// A wavy underline marks a finished word that is not in the dictionary.
/// Nothing is rewritten until the user picks a suggestion.
class EnglishSpellChecker extends ChangeNotifier {
  EnglishSpellChecker._(this._words);

  /// Small dictionary for tests.
  EnglishSpellChecker.forTest({required Set<String> words})
    : _words = {for (final word in words) word.toLowerCase()};

  static const _asset = 'assets/spelling/english_words.txt';
  static const _ignoreKey = 'spell_ignore_words';

  /// Words this app uses that a general dictionary does not list.
  static const Set<String> appWords = {
    'assignee',
    'assignees',
    'fundraising',
    'subproject',
    'subprojects',
    'subtask',
    'subtasks',
    'sub-project',
    'sub-projects',
    'sub-task',
    'sub-tasks',
    'hku',
    'pic',
    'daao',
    'login',
    'username',
    'webinar',
    'metadata',
  };

  static final _token = RegExp("[A-Za-z]+(?:['’-][A-Za-z]+)*");
  static const _letters = "abcdefghijklmnopqrstuvwxyz'";

  static Future<EnglishSpellChecker>? _loading;
  static EnglishSpellChecker? _instance;

  final Set<String> _words;
  final Set<String> _userIgnored = {};

  static Future<EnglishSpellChecker> ensureLoaded() {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    return _loading ??= _load();
  }

  static Future<EnglishSpellChecker> _load() async {
    final raw = await rootBundle.loadString(_asset);
    final words = <String>{};
    for (final line in raw.split('\n')) {
      final word = line.trim().toLowerCase();
      if (word.isEmpty || word.startsWith('#')) continue;
      words.add(word);
    }
    final checker = EnglishSpellChecker._(words);
    await checker._loadIgnored();
    _instance = checker;
    return checker;
  }

  Future<void> _loadIgnored() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_ignoreKey) ?? const <String>[];
      _userIgnored.addAll(saved.map((word) => word.toLowerCase()));
    } catch (_) {
      // Tests and a blocked browser store still spell-check; Ignore just
      // lasts for this visit.
    }
  }

  bool isKnown(String raw) {
    final word = raw.toLowerCase().replaceAll('’', "'");
    if (_words.contains(word) ||
        appWords.contains(word) ||
        _userIgnored.contains(word)) {
      return true;
    }
    if (word.endsWith("'s")) {
      final base = word.substring(0, word.length - 2);
      if (_words.contains(base) || appWords.contains(base)) return true;
    }
    return false;
  }

  /// Remember [raw] on this browser so it is not underlined again.
  Future<void> persistIgnore(String raw) async {
    final word = raw.toLowerCase().replaceAll('’', "'");
    if (word.isEmpty || _userIgnored.contains(word)) return;
    _userIgnored.add(word);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_ignoreKey, _userIgnored.toList());
    } catch (_) {}
  }

  TextRange? wordRangeAt(String text, int offset) {
    if (offset < 0) return null;
    for (final match in _token.allMatches(text)) {
      if (offset >= match.start && offset <= match.end) {
        return TextRange(start: match.start, end: match.end);
      }
    }
    return null;
  }

  List<SpellMiss> findMisspellings(String text, {TextRange? exclude}) {
    if (text.isEmpty) return const [];
    final misses = <SpellMiss>[];
    for (final match in _token.allMatches(text)) {
      final raw = match.group(0)!;
      if (exclude != null &&
          match.start >= exclude.start &&
          match.end <= exclude.end) {
        continue;
      }
      _collect(text, raw, match.start, misses);
    }
    return misses;
  }

  void _collect(String text, String raw, int start, List<SpellMiss> misses) {
    final end = start + raw.length;
    if (raw.length < 3 || _isAcronym(raw) || _skipEdge(text, start, end)) {
      return;
    }
    if (_lacksVowel(raw) && raw.length <= 6) return;
    if (isKnown(raw)) return;
    if (raw.contains('-') || raw.contains("'") || raw.contains('’')) {
      var partStart = start;
      for (final part in raw.split(RegExp("['’-]"))) {
        final partEnd = partStart + part.length;
        if (part.length >= 3 &&
            !_isAcronym(part) &&
            !(_lacksVowel(part) && part.length <= 6) &&
            !isKnown(part)) {
          misses.add(SpellMiss(partStart, partEnd, part));
        }
        partStart = partEnd + 1;
      }
      return;
    }
    misses.add(SpellMiss(start, end, raw));
  }

  List<String> suggestions(String raw, {int limit = 3}) {
    final word = raw.toLowerCase().replaceAll('’', "'");
    if (word.length < 3) return const [];
    final distance1 = _edits(word);
    final found = <String, int>{};
    for (final entry in distance1.entries) {
      if (isKnown(entry.key)) found[entry.key] = entry.value;
    }
    if (found.isEmpty && word.length <= 10) {
      for (final edited in distance1.keys) {
        for (final next in _edits(edited).keys) {
          if (next != word && isKnown(next)) {
            found.putIfAbsent(next, () => 4);
          }
        }
        if (found.length >= 24) break;
      }
    }
    final ranked = found.keys.toList()
      ..sort((a, b) {
        final kind = found[a]!.compareTo(found[b]!);
        if (kind != 0) return kind;
        final prefix = _sharedPrefix(b, word).compareTo(_sharedPrefix(a, word));
        if (prefix != 0) return prefix;
        return a.compareTo(b);
      });
    return [
      for (final suggestion in ranked.take(limit)) _matchCase(raw, suggestion),
    ];
  }

  static bool _isAcronym(String raw) {
    if (raw.length < 2 || raw.length > 6) return false;
    for (final code in raw.codeUnits) {
      final upper = code >= 0x41 && code <= 0x5a;
      if (!upper) return false;
    }
    return true;
  }

  static bool _lacksVowel(String raw) {
    return !RegExp('[AEIOUYaeiouy]').hasMatch(raw);
  }

  static bool _skipEdge(String text, int start, int end) {
    if (start > 0) {
      final previous = text[start - 1];
      if (previous == '@' || previous == '/' || previous == '.') return true;
    }
    if (end < text.length) {
      final next = text[end];
      if (next == '@' || next == ':') return true;
    }
    return false;
  }

  static int _sharedPrefix(String a, String b) {
    final n = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }

  static String _matchCase(String source, String suggestion) {
    if (source.isEmpty || suggestion.isEmpty) return suggestion;
    final letters = source.replaceAll(RegExp('[^A-Za-z]'), '');
    if (letters.length > 1 && letters == letters.toUpperCase()) {
      return suggestion.toUpperCase();
    }
    final tail = source.substring(1);
    if (source[0].toUpperCase() == source[0] && tail == tail.toLowerCase()) {
      return suggestion[0].toUpperCase() + suggestion.substring(1);
    }
    return suggestion;
  }

  /// 0 transpose, 1 replace, 2 delete, 3 insert.
  static Map<String, int> _edits(String word) {
    final best = <String, int>{};
    void add(String next, int kind) {
      if (next.isEmpty || next == word) return;
      final previous = best[next];
      if (previous == null || kind < previous) best[next] = kind;
    }

    for (var i = 0; i <= word.length; i++) {
      final left = word.substring(0, i);
      final right = word.substring(i);
      if (right.length > 1) {
        add(left + right[1] + right[0] + right.substring(2), 0);
      }
      if (right.isNotEmpty) {
        for (final unit in _letters.codeUnits) {
          add('$left${String.fromCharCode(unit)}${right.substring(1)}', 1);
        }
        add(left + right.substring(1), 2);
      }
      for (final unit in _letters.codeUnits) {
        add('$left${String.fromCharCode(unit)}$right', 3);
      }
    }
    return best;
  }
}
