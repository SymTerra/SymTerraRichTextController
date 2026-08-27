import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'layered_text_span.dart';

/// The default squiggle: a wavy red underline, matching platform convention.
const TextStyle kDefaultMisspelledStyle = TextStyle(
  decoration: TextDecoration.underline,
  decorationStyle: TextDecorationStyle.wavy,
  decorationColor: Color(0xFFD32F2F),
);

/// Adds a spell-check decoration layer to a [TextEditingController].
///
/// Flutter allows exactly one producer of a field's rendered text —
/// `TextEditingController.buildTextSpan` — and [EditableText] bypasses it
/// entirely once the framework's own spell check returns results. That is why
/// squiggles are rendered here rather than via [SpellCheckConfiguration]: it is
/// the only way for misspellings and pattern colours (mentions, hashtags) to
/// coexist in one span tree.
///
/// Feed ranges in with [setMisspelledRanges]; the controller notifies its
/// listeners and [EditableText] rebuilds.
mixin SpellCheckSpans on TextEditingController {
  List<TextRange> _misspelledRanges = const <TextRange>[];

  /// Ranges currently rendered as misspelled.
  List<TextRange> get misspelledRanges => _misspelledRanges;

  /// Style merged over misspelled ranges. Defaults to [kDefaultMisspelledStyle].
  TextStyle misspelledStyle = kDefaultMisspelledStyle;

  /// Replaces the misspelled ranges and rebuilds the field.
  ///
  /// A no-op when [ranges] matches what is already set — notifying
  /// unconditionally would rebuild [EditableText] on every check and, because
  /// each rebuild can trigger another check, spin.
  void setMisspelledRanges(List<TextRange> ranges) {
    final next = <TextRange>[
      for (final r in ranges)
        if (r.isValid && !r.isCollapsed) r,
    ];
    if (listEquals(_misspelledRanges, next)) return;
    _misspelledRanges = List<TextRange>.unmodifiable(next);
    notifyListeners();
  }

  /// Clears all squiggles.
  void clearMisspelledRanges() => setMisspelledRanges(const <TextRange>[]);

  /// The spell-check ranges as a decoration layer for [buildLayeredTextSpan].
  List<StyleRange> get spellCheckStyleRanges => <StyleRange>[
    for (final r in _misspelledRanges) StyleRange(start: r.start, end: r.end, style: misspelledStyle),
  ];

  /// Builds the span tree with squiggles (and the IME composing underline)
  /// merged on top of [exclusive] pattern ranges.
  @protected
  TextSpan buildSpellCheckedSpan({
    required String text,
    required bool withComposing,
    TextStyle? baseStyle,
    List<StyleRange> exclusive = const <StyleRange>[],
  }) {
    final decorations = <StyleRange>[...spellCheckStyleRanges];

    // Composing goes on last: while an IME is mid-word its underline is the
    // authoritative feedback, and the driver exempts the caret's word from
    // checking anyway.
    if (withComposing && value.isComposingRangeValid && !value.composing.isCollapsed) {
      decorations.add(
        StyleRange(
          start: value.composing.start,
          end: value.composing.end,
          style: const TextStyle(decoration: TextDecoration.underline),
        ),
      );
    }

    return buildLayeredTextSpan(
      text: text,
      baseStyle: baseStyle,
      exclusive: exclusive,
      decorations: decorations,
    );
  }

  /// Replaces `[start, end)` with [replacement] and puts the caret after it.
  ///
  /// Use this for suggestion replacement rather than assigning to `text`.
  /// Controllers that track token offsets override this to keep that
  /// bookkeeping correct.
  void replaceRange(int start, int end, String replacement) {
    final current = text;
    final from = start.clamp(0, current.length);
    final to = end.clamp(from, current.length);
    if (from == to && replacement.isEmpty) return;
    value = TextEditingValue(
      text: current.replaceRange(from, to, replacement),
      selection: TextSelection.collapsed(offset: from + replacement.length),
    );
  }
}

/// A [TextEditingController] with spell-check squiggles and no pattern styling.
///
/// For plain fields (report answers, quick-note composer without mentions) that
/// need squiggles but none of the token behaviour of
/// `SymTerraRichTextController`.
class SpellCheckableTextEditingController extends TextEditingController with SpellCheckSpans {
  SpellCheckableTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, bool withComposing = false}) {
    return buildSpellCheckedSpan(text: value.text, baseStyle: style, withComposing: withComposing);
  }
}
