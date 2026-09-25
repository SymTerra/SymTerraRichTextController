import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symterra_rich_text_controller/symterra_rich_text_controller.dart';

const mentionRegex = r'@\b[a-zA-Z][a-zA-Z0-9]*(?:_[a-zA-Z][a-zA-Z0-9]*)+\b';
const tagRegex = r'(?<=\s|^)#(\w+)';

const teal = Color(0xFF00A3A1);
const blue = Color(0xFF3B5BA9);

SymTerraRichTextController buildController({
  String text = '',
  void Function(DeletedToken)? onAnyDeleted,
}) {
  return SymTerraRichTextController(
    text: text,
    onAnyDeleted: onAnyDeleted,
    patterns: [
      PatternStyle(key: 'mention', pattern: RegExp(mentionRegex), style: const TextStyle(color: teal), trigger: '@'),
      PatternStyle(key: 'hashtag', pattern: RegExp(tagRegex), style: const TextStyle(color: blue), trigger: '#'),
    ],
  );
}

/// Flattens a span tree into (text, style) leaves.
List<(String, TextStyle?)> leaves(InlineSpan span) {
  final out = <(String, TextStyle?)>[];
  span.visitChildren((child) {
    if (child is TextSpan) {
      if (child.text != null && child.text!.isNotEmpty) out.add((child.text!, child.style));
      for (final grandchild in child.children ?? const <InlineSpan>[]) {
        out.addAll(leaves(grandchild));
      }
    }
    return true;
  });
  return out;
}

(String, TextStyle?) leafContaining(InlineSpan span, String needle) =>
    leaves(span).firstWhere((l) => l.$1.contains(needle), orElse: () => throw StateError('no leaf with "$needle" in ${leaves(span)}'));

TextRange rangeOf(String text, String word) {
  final start = text.indexOf(word);
  if (start < 0) throw ArgumentError('"$word" not in "$text"');
  return TextRange(start: start, end: start + word.length);
}

/// `buildTextSpan` takes a `BuildContext` only because it overrides
/// `TextEditingController.buildTextSpan`; the span is built from controller
/// state alone. Passing a context that throws on any access keeps these as plain
/// unit tests — per the house unit-plus-integration policy — and asserts that
/// independence rather than just assuming it.
class _UnusedContext implements BuildContext {
  const _UnusedContext();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('buildTextSpan must not read its BuildContext');
}

void main() {
  group('buildLayeredTextSpan', () {
    test('returns a plain span when there are no ranges', () {
      final span = buildLayeredTextSpan(text: 'hello', baseStyle: const TextStyle(fontSize: 12));
      expect(span.text, 'hello');
      expect(span.style?.fontSize, 12);
    });

    test('merges a decoration over an exclusive colour instead of dropping one', () {
      final span = buildLayeredTextSpan(
        text: 'abc def',
        exclusive: [StyleRange(start: 0, end: 3, style: const TextStyle(color: teal))],
        decorations: [StyleRange(start: 1, end: 2, style: const TextStyle(decoration: TextDecoration.underline))],
      );
      final both = leafContaining(span, 'b');
      expect(both.$2?.color, teal, reason: 'exclusive colour must survive');
      expect(both.$2?.decoration, TextDecoration.underline, reason: 'decoration must also apply');
      // the 'a' slice keeps the colour but has no decoration
      expect(leafContaining(span, 'a').$2?.decoration, isNull);
    });

    test('resolves overlapping exclusive ranges by priority, lower wins', () {
      final span = buildLayeredTextSpan(
        text: 'abcdef',
        exclusive: [
          StyleRange(start: 0, end: 4, style: const TextStyle(color: blue), priority: 1),
          StyleRange(start: 0, end: 6, style: const TextStyle(color: teal), priority: 0),
        ],
      );
      expect(leafContaining(span, 'a').$2?.color, teal);
    });

    test('clamps out-of-bounds ranges instead of throwing', () {
      final span = buildLayeredTextSpan(
        text: 'abc',
        decorations: [StyleRange(start: 1, end: 99, style: const TextStyle(decoration: TextDecoration.underline))],
      );
      expect(leaves(span).map((l) => l.$1).join(), 'abc');
    });

    test('coalesces adjacent slices with identical styles', () {
      final span = buildLayeredTextSpan(
        text: 'abcdef',
        decorations: [
          StyleRange(start: 0, end: 3, style: const TextStyle(decoration: TextDecoration.underline)),
          StyleRange(start: 3, end: 6, style: const TextStyle(decoration: TextDecoration.underline)),
        ],
      );
      expect(leaves(span).length, 1, reason: 'one uniform run, not two');
    });
  });

  group('setMisspelledRanges', () {
    test('does not notify when the ranges are unchanged', () {
      final controller = buildController(text: 'helo world');
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setMisspelledRanges([rangeOf('helo world', 'helo')]);
      expect(notifications, 1);

      controller.setMisspelledRanges([rangeOf('helo world', 'helo')]);
      expect(notifications, 1, reason: 'identical ranges must not rebuild the field');
    });

    test('notifies when the ranges actually change', () {
      final controller = buildController(text: 'helo world');
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setMisspelledRanges([rangeOf('helo world', 'helo')]);
      controller.setMisspelledRanges([rangeOf('helo world', 'world')]);
      expect(notifications, 2);
    });

    test('drops invalid and collapsed ranges', () {
      final controller = buildController(text: 'helo');
      controller.setMisspelledRanges([
        const TextRange(start: 2, end: 2),
        TextRange.empty,
      ]);
      expect(controller.misspelledRanges, isEmpty);
    });
  });

  group('buildTextSpan with patterns and squiggles', () {
    test('a typo inside a hashtag keeps both the hashtag colour and the squiggle', () {
      const text = 'see #Delayy now';
      final controller = buildController(text: text);
      controller.setMisspelledRanges([rangeOf(text, 'Delayy')]);

      final span = controller.buildTextSpan(context: const _UnusedContext(), style: const TextStyle(fontSize: 14));

      final leaf = leafContaining(span, 'Delayy');
      expect(leaf.$2?.color, blue, reason: 'hashtag colour must survive the squiggle');
      expect(leaf.$2?.decoration, TextDecoration.underline);
      expect(leaf.$2?.decorationStyle, TextDecorationStyle.wavy);
      expect(leaf.$2?.fontSize, 14, reason: 'base style must still merge through');
    });

    test('mention colour survives while an unrelated word is misspelled', () {
      const text = 'Helo @John_Smith';
      final controller = buildController(text: text);
      controller.setMisspelledRanges([rangeOf(text, 'Helo')]);

      final span = controller.buildTextSpan(context: const _UnusedContext(), style: const TextStyle());

      expect(leafContaining(span, '@John_Smith').$2?.color, teal);
      expect(leafContaining(span, '@John_Smith').$2?.decoration, isNull,
          reason: 'mentions are skipped by the tokenizer and must never be squiggled');
      expect(leafContaining(span, 'Helo').$2?.decoration, TextDecoration.underline);
    });

    test('renders the composing underline when withComposing is set', () {
      final controller = buildController(text: 'abc def');
      controller.value = const TextEditingValue(
        text: 'abc def',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 4, end: 7),
      );

      final span = controller.buildTextSpan(context: const _UnusedContext(), style: const TextStyle(), withComposing: true);

      expect(leafContaining(span, 'def').$2?.decoration, TextDecoration.underline);
    });
  });

  group('replaceRange', () {
    test('replaces the word and puts the caret after it', () {
      final controller = buildController(text: 'teh cat');
      controller.replaceRange(0, 3, 'the');
      expect(controller.text, 'the cat');
      expect(controller.selection.baseOffset, 3);
    });

    test('shifts a mention that sits after the replacement', () {
      final controller = buildController();
      controller.value = const TextEditingValue(text: 'teh ', selection: TextSelection.collapsed(offset: 4));
      controller.insertToken(patternKey: 'mention', visibleText: '@John_Smith', tokenId: 'u1', label: 'John Smith');
      final before = controller.idTokens.single;
      expect(controller.text, 'teh @John_Smith');

      controller.replaceRange(0, 3, 'the');

      final after = controller.idTokens.single;
      expect(controller.text, 'the @John_Smith');
      expect(after.id, 'u1');
      expect(after.start, before.start, reason: 'same-length replacement must not move the token');
      expect(controller.text.substring(after.start, after.end), '@John_Smith');
    });

    test('shifts a trailing mention when the replacement changes length', () {
      final controller = buildController();
      controller.value = const TextEditingValue(text: 'wrng ', selection: TextSelection.collapsed(offset: 5));
      controller.insertToken(patternKey: 'mention', visibleText: '@John_Smith', tokenId: 'u1', label: 'John Smith');

      controller.replaceRange(0, 4, 'wrong');

      final token = controller.idTokens.single;
      expect(controller.text, 'wrong @John_Smith');
      expect(controller.text.substring(token.start, token.end), '@John_Smith',
          reason: 'token offsets must track the length delta');
    });

    test('leaves a mention before the replacement untouched', () {
      final controller = buildController();
      controller.insertToken(patternKey: 'mention', visibleText: '@John_Smith', tokenId: 'u1', label: 'John Smith');
      controller.value = TextEditingValue(
        text: '${controller.text} teh',
        selection: const TextSelection.collapsed(offset: 15),
      );
      final before = controller.idTokens.single.start;

      controller.replaceRange(12, 15, 'the');

      expect(controller.text, '@John_Smith the');
      expect(controller.idTokens.single.start, before);
    });

    test('reports the token and drops it when a replacement overlaps a mention', () {
      final deleted = <DeletedToken>[];
      final controller = buildController(onAnyDeleted: deleted.add);
      controller.insertToken(patternKey: 'mention', visibleText: '@John_Smith', tokenId: 'u1', label: 'John Smith');

      controller.replaceRange(0, 5, 'x');

      expect(controller.idTokens, isEmpty, reason: 'a disturbed token must not keep stale offsets');
      expect(deleted.map((d) => d.tokenId), contains('u1'), reason: 'the app must be told to drop the mention');
    });

    test('is a no-op for an empty replacement over an empty range', () {
      final controller = buildController(text: 'stable');
      controller.replaceRange(3, 3, '');
      expect(controller.text, 'stable');
    });
  });

  group('squiggle bookkeeping across edits', () {
    test('accepting a suggestion clears that word and re-bases the ones after it', () {
      const before = 'teh see #Delayy';
      final controller = buildController(text: before);
      controller.setMisspelledRanges([rangeOf(before, 'teh'), rangeOf(before, 'Delayy')]);

      controller.replaceRange(0, 3, 'their');

      expect(controller.text, 'their see #Delayy');
      // The corrected word's squiggle is gone, not left over the new text.
      expect(controller.misspelledRanges.length, 1);
      final r = controller.misspelledRanges.single;
      expect(controller.text.substring(r.start, r.end), 'Delayy');
    });

    test('a same-length correction still drops the squiggle it replaced', () {
      const before = 'teh end';
      final controller = buildController(text: before);
      controller.setMisspelledRanges([rangeOf(before, 'teh')]);

      controller.replaceRange(0, 3, 'the');

      expect(controller.text, 'the end');
      expect(controller.misspelledRanges, isEmpty);
    });

    test('a range entirely before the edit is untouched', () {
      const before = 'helo and teh';
      final controller = buildController(text: before);
      controller.setMisspelledRanges([rangeOf(before, 'helo')]);

      controller.replaceRange(9, 12, 'the');

      final r = controller.misspelledRanges.single;
      expect(controller.text.substring(r.start, r.end), 'helo');
    });

    test('shrinking the text never leaves a range past its end', () {
      const before = 'alpha beta gamma';
      final controller = buildController(text: before);
      controller.setMisspelledRanges([rangeOf(before, 'gamma')]);

      controller.replaceRange(0, 6, '');

      for (final r in controller.misspelledRanges) {
        expect(r.end, lessThanOrEqualTo(controller.text.length));
      }
    });
  });

  group('replaceRange deletion reporting', () {
    test('a token the edit destroys is reported', () {
      final deleted = <DeletedToken>[];
      final controller = buildController(text: 'see #Delayy now', onAnyDeleted: deleted.add);

      controller.replaceRange(4, 11, 'ok');

      expect(controller.text, 'see ok now');
      expect(deleted.map((d) => d.text), contains('#Delayy'));
    });

    test('a token that survives an edit inside it is not reported deleted', () {
      final deleted = <DeletedToken>[];
      final controller = buildController(text: 'see #Delayy now', onAnyDeleted: deleted.add);

      // Correct the typo inside the hashtag: "#Delayy" -> "#Delay".
      controller.replaceRange(5, 11, 'Delay');

      expect(controller.text, 'see #Delay now');
      expect(deleted, isEmpty, reason: 'the hashtag is still on screen');
    });
  });

  group('replaceRange argument handling', () {
    test('reversed arguments do not append', () {
      final controller = buildController(text: 'abcdef');
      controller.replaceRange(5, 1, 'X');
      expect(controller.text.length, lessThanOrEqualTo('abcdef'.length + 1));
      expect(controller.text.endsWith('X'), isFalse, reason: 'must not silently append');
    });

    test('out-of-bounds arguments are clamped', () {
      final controller = buildController(text: 'abc');
      controller.replaceRange(-5, 99, 'Z');
      expect(controller.text, 'Z');
    });
  });

  group('squiggle bookkeeping on every edit path', () {
    test('typing in front of a squiggle moves it with the text', () {
      const before = 'helo world';
      final c = buildController(text: before);
      c.setMisspelledRanges([rangeOf(before, 'helo')]);
      c.selection = const TextSelection.collapsed(offset: 0);

      c.value = const TextEditingValue(text: 'Xhelo world', selection: TextSelection.collapsed(offset: 1));

      final r = c.misspelledRanges.single;
      expect(c.text.substring(r.start, r.end), 'helo', reason: 'the squiggle must follow the word, not stay at offset 0');
    });

    test('deleting text before a squiggle never leaves a range past the end', () {
      const before = 'alpha beta';
      final c = buildController(text: before);
      c.setMisspelledRanges([rangeOf(before, 'beta')]);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 6);

      c.value = const TextEditingValue(text: 'beta', selection: TextSelection.collapsed(offset: 0));

      for (final r in c.misspelledRanges) {
        expect(r.end, lessThanOrEqualTo(c.text.length));
        // The public getter must never hand back something substring() rejects.
        expect(() => c.text.substring(r.start, r.end), returnsNormally);
      }
    });

    test('insertToken re-bases squiggles after the inserted text', () {
      const before = 'see teh end';
      final c = buildController(text: before);
      c.setMisspelledRanges([rangeOf(before, 'teh')]);
      c.selection = const TextSelection.collapsed(offset: 4);

      c.insertToken(patternKey: 'mention', visibleText: '@John_Smith', tokenId: 'u1', label: 'John Smith');

      for (final r in c.misspelledRanges) {
        expect(() => c.text.substring(r.start, r.end), returnsNormally);
      }
    });

    test('an atomic token deletion leaves no out-of-range squiggle', () {
      final c = buildController(text: 'see @John_Smith teh end');
      c.setMisspelledRanges([rangeOf('see @John_Smith teh end', 'teh')]);
      c.selection = const TextSelection.collapsed(offset: 15);

      // Backspace into the mention: the whole token goes atomically.
      c.value = const TextEditingValue(text: 'see @John_Smit teh end', selection: TextSelection.collapsed(offset: 14));

      for (final r in c.misspelledRanges) {
        expect(() => c.text.substring(r.start, r.end), returnsNormally);
      }
    });
  });

  group('deletion reporting', () {
    test('a whole-token rewrite is reported deleted', () {
      final deleted = <DeletedToken>[];
      final c = buildController(text: 'see #Alpha now', onAnyDeleted: deleted.add);

      c.replaceRange(4, 10, '#Beta');

      expect(c.text, 'see #Beta now');
      expect(
        deleted.map((d) => d.text),
        contains('#Alpha'),
        reason: '#Alpha no longer exists anywhere; the app must be told to drop it',
      );
    });

    test('a typo corrected inside a token is still not reported', () {
      final deleted = <DeletedToken>[];
      final c = buildController(text: 'see #Delayy now', onAnyDeleted: deleted.add);

      c.replaceRange(5, 11, 'Delay');

      expect(c.text, 'see #Delay now');
      expect(deleted, isEmpty, reason: 'the hashtag is still on screen');
    });
  });

  group('selection deletion', () {
    test('select-all delete removes everything, not just the tokens', () {
      final c = buildController(text: 'hello @john_doe world');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 21);

      c.value = const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));

      expect(c.text, isEmpty, reason: 'the non-token text between and around tokens must go too');
    });

    test('deleting a multi-token selection leaves no stale id offsets', () {
      final c = buildController(text: '@aaa_bbb @ccc_ddd');
      c.insertToken(patternKey: 'mention', visibleText: '@aaa_bbb', tokenId: 'u1');
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);

      c.value = TextEditingValue(text: '', selection: const TextSelection.collapsed(offset: 0));

      for (final tok in c.idTokens) {
        expect(tok.end, lessThanOrEqualTo(c.text.length), reason: 'an id token cannot outlive the text it indexed');
      }
    });
  });

  group('SpellCheckableTextEditingController', () {
    test('squiggles without any pattern styling', () {
      final controller = SpellCheckableTextEditingController(text: 'helo there');
      controller.setMisspelledRanges([rangeOf('helo there', 'helo')]);

      final span = controller.buildTextSpan(context: const _UnusedContext(), style: const TextStyle(color: Colors.black));

      expect(leafContaining(span, 'helo').$2?.decorationStyle, TextDecorationStyle.wavy);
      expect(leafContaining(span, 'there').$2?.decoration, isNull);
    });

    test('replaceRange works through the plain controller', () {
      final controller = SpellCheckableTextEditingController(text: 'teh end');
      controller.replaceRange(0, 3, 'the');
      expect(controller.text, 'the end');
      expect(controller.selection.baseOffset, 3);
    });
  });
}
