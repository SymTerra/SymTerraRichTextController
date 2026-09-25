import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symterra_rich_text_controller/symterra_rich_text_controller.dart';

/// A controller whose spell-check layer is broken.
class _BrokenSpellLayer extends TextEditingController with SpellCheckSpans {
  _BrokenSpellLayer({super.text});

  @override
  List<StyleRange> get spellCheckStyleRanges => throw StateError('engine produced garbage');

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, bool withComposing = false}) {
    return buildSpellCheckedSpan(
      text: value.text,
      baseStyle: style,
      withComposing: withComposing,
      exclusive: <StyleRange>[
        StyleRange(start: 0, end: 5, style: const TextStyle(color: Color(0xFF00FF00))),
      ],
    );
  }
}

/// A base style that throws whenever anything is merged onto it, so both the
/// decorated and the pattern-only build fail and only the last resort is left.
class _ThrowingStyle extends TextStyle {
  const _ThrowingStyle();

  @override
  TextStyle merge(TextStyle? other) => throw StateError('style merge exploded');
}

String _plainText(InlineSpan span) {
  final buffer = StringBuffer();
  span.visitChildren((child) {
    if (child is TextSpan && child.text != null) buffer.write(child.text);
    return true;
  });
  return buffer.toString();
}

void main() {
  late List<FlutterErrorDetails> reported;
  late void Function(FlutterErrorDetails)? previous;

  setUp(() {
    reported = <FlutterErrorDetails>[];
    previous = FlutterError.onError;
    FlutterError.onError = reported.add;
  });

  tearDown(() => FlutterError.onError = previous);

  /// The guarantee: a broken spell-check layer costs the squiggles, never the
  /// field. A throw reaching EditableText's build replaces the whole composer
  /// with an ErrorWidget, which is the user losing their note over a squiggle.
  test('a throwing spell-check layer still renders the text, keeping pattern colours', () {
    final controller = _BrokenSpellLayer(text: 'hello world');
    addTearDown(controller.dispose);

    final span = controller.buildTextSpan(
          context: _throwingContext,
          style: const TextStyle(fontSize: 14),
          withComposing: false,
        );

    expect(span.toPlainText(), 'hello world');
    // The pattern layer survives: only the spell-check decorations were dropped,
    // so the span is still a styled tree rather than one flat run.
    expect(span.children, isNotNull);
    expect(_plainText(span), contains('hello'));
    expect(reported, hasLength(1));
    expect(reported.single.context.toString(), contains('decorated'));
  });

  test('a throw in both layers still renders the text unstyled', () {
    final controller = _BrokenSpellLayer(text: 'hello world');
    addTearDown(controller.dispose);

    final span = controller.buildTextSpan(
          context: _throwingContext,
          style: const _ThrowingStyle(),
          withComposing: false,
        );

    expect(span.toPlainText(), 'hello world');
    // The last resort is one flat run: every styling layer was abandoned.
    expect(span.children, isNull);
    expect(reported, hasLength(2));
    expect(reported.last.context.toString(), contains('pattern-only'));
  });

  test('a reporting failure never becomes the thing that breaks the field', () {
    FlutterError.onError = (_) => throw StateError('the reporter is broken too');
    final controller = _BrokenSpellLayer(text: 'hello world');
    addTearDown(controller.dispose);

    final span = controller.buildTextSpan(context: _throwingContext, style: null, withComposing: false);

    expect(span.toPlainText(), 'hello world');
  });
}

/// buildTextSpan takes a context only to satisfy the override; touching it is a bug.
final BuildContext _throwingContext = _ThrowingContext();

class _ThrowingContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('buildTextSpan must not touch its context');
}
