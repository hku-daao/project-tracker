import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../services/english_spell_checker.dart';
import 'asana_theme.dart';

/// Draws a red wavy underline for misspellings and opens suggestions on click.
///
/// The field keeps the caller's [controller]. A replacement is written only
/// when the user clicks a suggestion.
class AsanaSpellCheckBinding extends StatefulWidget {
  const AsanaSpellCheckBinding({
    super.key,
    required this.controller,
    required this.enabled,
    required this.builder,
    this.interactive = true,
    this.onTextReplaced,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool interactive;
  final ValueChanged<String>? onTextReplaced;
  final Widget Function(TextEditingController controller, VoidCallback? onTap)
  builder;

  @override
  State<AsanaSpellCheckBinding> createState() => _AsanaSpellCheckBindingState();
}

class _AsanaSpellCheckBindingState extends State<AsanaSpellCheckBinding> {
  _SpellTextController? _spell;
  EnglishSpellChecker? _checker;
  Timer? _timer;
  bool _syncing = false;
  bool _silent = false;
  bool _applying = false;
  bool _excludeActive = false;
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _attach();
    EnglishSpellChecker.ensureLoaded().then((checker) {
      if (!mounted) return;
      _checker = checker;
      checker.addListener(_onDictionary);
      _scheduleRecheck(excludeActive: false);
    });
  }

  @override
  void didUpdateWidget(AsanaSpellCheckBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onSource);
      if (widget.enabled) widget.controller.addListener(_onSource);
    }
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        _attach();
      } else {
        _detachField();
      }
    } else if (widget.enabled) {
      _onSource();
    }
  }

  void _attach() {
    _detachField();
    final spell = _SpellTextController(widget.controller.value);
    spell.addListener(_onSpell);
    widget.controller.addListener(_onSource);
    _spell = spell;
    _scheduleRecheck(excludeActive: false);
  }

  void _detachField() {
    _timer?.cancel();
    _hideMenu();
    _spell?.removeListener(_onSpell);
    widget.controller.removeListener(_onSource);
    _spell?.dispose();
    _spell = null;
  }

  @override
  void dispose() {
    _checker?.removeListener(_onDictionary);
    _detachField();
    super.dispose();
  }

  void _onDictionary() => _scheduleRecheck(excludeActive: false);

  void _onSource() {
    final spell = _spell;
    if (_syncing || spell == null) return;
    if (spell.value == widget.controller.value) return;
    _syncing = true;
    spell.value = widget.controller.value;
    _syncing = false;
    _scheduleRecheck(excludeActive: false);
  }

  void _onSpell() {
    final spell = _spell;
    if (_syncing || _silent || spell == null) return;
    final textChanged = spell.text != widget.controller.text;
    _syncing = true;
    widget.controller.value = spell.value;
    _syncing = false;
    if (!textChanged) return;
    _hideMenu();
    _scheduleRecheck(excludeActive: !_applying);
    if (_applying) widget.onTextReplaced?.call(spell.text);
  }

  void _scheduleRecheck({required bool excludeActive}) {
    _excludeActive = excludeActive;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      _recheck(excludeActive: _excludeActive);
    });
  }

  void _recheck({required bool excludeActive}) {
    final checker = _checker;
    final spell = _spell;
    if (checker == null || spell == null || !widget.enabled) return;
    TextRange? exclude;
    if (excludeActive && spell.selection.isValid && spell.selection.isCollapsed) {
      exclude = checker.wordRangeAt(spell.text, spell.selection.extentOffset);
    }
    final hits = checker.findMisspellings(spell.text, exclude: exclude);
    if (_sameHits(spell.hits, hits)) return;
    _silent = true;
    spell.setHits(hits);
    _silent = false;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!widget.interactive || _menuOpen) return;
    final global = event.position;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _menuOpen) return;
      _offerReplacement(global);
    });
  }

  Future<void> _offerReplacement(Offset global) async {
    final spell = _spell;
    final checker = _checker;
    if (spell == null || checker == null || !widget.interactive) return;
    _timer?.cancel();
    _recheck(excludeActive: false);
    final hit = _hitAtPoint(global) ?? _hitInSelection(spell);
    if (hit == null) return;
    final suggestions = checker.suggestions(hit.word);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.hasSize) return;
    final local = overlayBox.globalToLocal(global);
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(local.dx, local.dy, 0, 0),
      Offset.zero & overlayBox.size,
    );
    _menuOpen = true;
    _SpellChoice? choice;
    try {
      choice = await showMenu<_SpellChoice>(
        context: context,
        useRootNavigator: true,
        requestFocus: false,
        position: position,
        color: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        items: [
          if (suggestions.isEmpty)
            const PopupMenuItem<_SpellChoice>(
              enabled: false,
              child: Text('No suggestions'),
            )
          else
            for (final suggestion in suggestions)
              PopupMenuItem<_SpellChoice>(
                value: _SpellChoice.replace(suggestion),
                height: 48,
                child: Text(
                  suggestion,
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.bodyMedium,
                    fontSize: 16,
                    color: kAsanaTextPrimary,
                  ),
                ),
              ),
          const PopupMenuItem<_SpellChoice>(
            value: _SpellChoice.ignore(),
            height: 48,
            child: Text('Ignore'),
          ),
        ],
      );
    } finally {
      _menuOpen = false;
    }
    if (!mounted || choice == null) return;
    if (choice.ignore) {
      await checker.persistIgnore(hit.word);
      return;
    }
    final replacement = choice.text;
    if (replacement == null || replacement.isEmpty) return;
    _apply(hit, replacement);
  }

  SpellMiss? _hitAtPoint(Offset global) {
    final spell = _spell;
    if (spell == null) return null;
    final editable = _findEditable();
    if (editable == null || !editable.attached || !editable.hasSize) {
      return null;
    }
    late final int offset;
    try {
      offset = editable.getPositionForPoint(global).offset;
    } catch (_) {
      return null;
    }
    return _hitCovering(spell.hits, offset);
  }

  SpellMiss? _hitInSelection(_SpellTextController spell) {
    final selection = spell.selection;
    if (!selection.isValid) return null;
    if (selection.isCollapsed) {
      return _hitCovering(spell.hits, selection.extentOffset);
    }
    final from = selection.start < selection.end
        ? selection.start
        : selection.end;
    final to = selection.start < selection.end ? selection.end : selection.start;
    for (final hit in spell.hits) {
      if (hit.start < to && hit.end > from) return hit;
    }
    return null;
  }

  SpellMiss? _hitCovering(List<SpellMiss> hits, int offset) {
    for (final hit in hits) {
      if (offset >= hit.start && offset <= hit.end) return hit;
    }
    return null;
  }

  RenderEditable? _findEditable() {
    RenderEditable? found;
    void visit(Element element) {
      if (found != null) return;
      final render = element.renderObject;
      if (render is RenderEditable && render.hasSize) {
        found = render;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  void _apply(SpellMiss miss, String suggestion) {
    final spell = _spell;
    if (spell == null) return;
    final text = spell.text;
    if (miss.start < 0 || miss.end > text.length || miss.start >= miss.end) {
      _hideMenu();
      return;
    }
    final next = text.replaceRange(miss.start, miss.end, suggestion);
    final offset = miss.start + suggestion.length;
    _hideMenu();
    _applying = true;
    spell.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset),
    );
    _applying = false;
  }

  void _hideMenu() {
    if (!_menuOpen || !mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) navigator.pop();
    _menuOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _spell == null) {
      return widget.builder(widget.controller, null);
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: _onPointerUp,
      child: widget.builder(_spell!, null),
    );
  }
}

class _SpellChoice {
  const _SpellChoice.replace(this.text) : ignore = false;
  const _SpellChoice.ignore() : text = null, ignore = true;

  final String? text;
  final bool ignore;
}

bool _sameHits(List<SpellMiss> a, List<SpellMiss> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].start != b[i].start ||
        a[i].end != b[i].end ||
        a[i].word != b[i].word) {
      return false;
    }
  }
  return true;
}

class _SpellTextController extends TextEditingController {
  _SpellTextController(super.value) : super.fromValue();

  List<SpellMiss> hits = const [];

  void setHits(List<SpellMiss> next) {
    hits = next;
    notifyListeners();
  }

  static const _wavy = TextStyle(
    decoration: TextDecoration.underline,
    decorationColor: Color(0xFFD32F2F),
    decorationStyle: TextDecorationStyle.wavy,
    decorationThickness: 1.6,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final value = text;
    final usable = <SpellMiss>[
      for (final hit in hits)
        if (hit.start >= 0 &&
            hit.end <= value.length &&
            hit.start < hit.end &&
            value.substring(hit.start, hit.end) == hit.word)
          hit,
    ];
    if (usable.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final hit in usable) {
      if (hit.start < cursor) continue;
      if (hit.start > cursor) {
        children.add(TextSpan(text: value.substring(cursor, hit.start)));
      }
      children.add(
        TextSpan(text: value.substring(hit.start, hit.end), style: _wavy),
      );
      cursor = hit.end;
    }
    if (cursor < value.length) {
      children.add(TextSpan(text: value.substring(cursor)));
    }
    return TextSpan(style: style, children: children);
  }
}

