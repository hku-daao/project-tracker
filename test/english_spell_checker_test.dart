import 'package:flutter_test/flutter_test.dart';
import 'package:project_tracker/services/english_spell_checker.dart';

void main() {
  EnglishSpellChecker checker() {
    return EnglishSpellChecker.forTest(
      words: {
        'receive',
        'the',
        'project',
        'colour',
        'organisation',
        'well',
        'known',
        'please',
        'updated',
        'step',
        "don't",
      },
    );
  }

  test('underlines a finished misspelling and suggests the word', () {
    final spell = checker();
    final misses = spell.findMisspellings('Please recieve the project');
    expect(misses.map((miss) => miss.word).toList(), ['recieve']);
    expect(spell.suggestions('recieve'), contains('receive'));
    expect(spell.suggestions('Recieve'), contains('Receive'));
    expect(spell.suggestions('teh'), contains('the'));
  });

  test('leaves acronyms, app words, and known spellings alone', () {
    final spell = checker();
    final misses = spell.findMisspellings(
      'HKU PIC assignee updated the sub-project colour',
    );
    expect(misses, isEmpty);
  });

  test('marks only the bad part of a hyphenated word', () {
    final spell = checker();
    final misses = spell.findMisspellings('A well-knowm step');
    expect(misses.map((miss) => miss.word).toList(), ['knowm']);
  });

  test('skips the word still being typed', () {
    final spell = checker();
    const text = 'Please recieve';
    final active = spell.wordRangeAt(text, text.length);
    final misses = spell.findMisspellings(text, exclude: active);
    expect(misses, isEmpty);
  });

  test('ignore hides a word', () async {
    final spell = checker();
    expect(spell.findMisspellings('recieve'), isNotEmpty);
    await spell.persistIgnore('recieve');
    expect(spell.findMisspellings('recieve'), isEmpty);
  });

  test('bundled list accepts British spelling', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final spell = await EnglishSpellChecker.ensureLoaded();
    expect(
      spell.findMisspellings(
        'Please colour the organisation and recognise the centre',
      ),
      isEmpty,
    );
    expect(
      spell.findMisspellings('The assignee updated the sub-project'),
      isEmpty,
    );
    expect(
      spell.findMisspellings('Please recieve teh project').map((m) => m.word),
      ['recieve', 'teh'],
    );
  });
}