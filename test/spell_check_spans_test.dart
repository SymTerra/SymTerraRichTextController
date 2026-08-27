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
    testWidgets('a typo inside a hashtag keeps both the hashtag colour and the squiggle', (tester) async {
      const text = 'see #Delayy now';
      final controller = buildController(text: text);
      controller.setMisspelledRanges([rangeOf(text, 'Delayy')]);

      late TextSpan span;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              span = controller.buildTextSpan(context: context, style: const TextStyle(fontSize: 14));
              return const SizedBox();
            },
          ),
        ),
      );

      final leaf = leafContaining(span, 'Delayy');
      expect(leaf.$2?.color, blue, reason: 'hashtag colour must survive the squiggle');
      expect(leaf.$2?.decoration, TextDecoration.underline);
      expect(leaf.$2?.decorationStyle, TextDecorationStyle.wavy);
      expect(leaf.$2?.fontSize, 14, reason: 'base style must still merge through');
    });

    testWidgets('mention colour survives while an unrelated word is misspelled', (tester) async {
      const text = 'Helo @John_Smith';
      final controller = buildController(text: text);
      controller.setMisspelledRanges([rangeOf(text, 'Helo')]);

      late TextSpan span;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              span = controller.buildTextSpan(context: context, style: const TextStyle());
              return const SizedBox();
            },
          ),
        ),
      );

      expect(leafContaining(span, '@John_Smith').$2?.color, teal);
      expect(leafContaining(span, '@John_Smith').$2?.decoration, isNull,
          reason: 'mentions are skipped by the tokenizer and must never be squiggled');
      expect(leafContaining(span, 'Helo').$2?.decoration, TextDecoration.underline);
    });

    testWidgets('renders the composing underline when withComposing is set', (tester) async {
      final controller = buildController(text: 'abc def');
      controller.value = const TextEditingValue(
        text: 'abc def',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 4, end: 7),
      );

      late TextSpan span;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              span = controller.buildTextSpan(context: context, style: const TextStyle(), withComposing: true);
              return const SizedBox();
            },
          ),
        ),
      );

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

  group('SpellCheckableTextEditingController', () {
    testWidgets('squiggles without any pattern styling', (tester) async {
      final controller = SpellCheckableTextEditingController(text: 'helo there');
      controller.setMisspelledRanges([rangeOf('helo there', 'helo')]);

      late TextSpan span;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              span = controller.buildTextSpan(context: context, style: const TextStyle(color: Colors.black));
              return const SizedBox();
            },
          ),
        ),
      );

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
