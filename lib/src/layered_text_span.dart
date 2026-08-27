import 'package:flutter/material.dart';

/// A styled range contributed to one layer of a [TextSpan] tree.
///
/// Used by [buildLayeredTextSpan]. Ranges are half-open: `[start, end)`.
@immutable
class StyleRange {
  const StyleRange({required this.start, required this.end, required this.style, this.priority = 0});

  /// Inclusive start offset in the source text.
  final int start;

  /// Exclusive end offset in the source text.
  final int end;

  /// Style contributed by this range.
  final TextStyle style;

  /// Precedence when ranges collide in the *exclusive* layer — lower wins.
  ///
  /// Ignored for the decoration layer, where every range is merged.
  final int priority;

  @override
  bool operator ==(Object other) =>
      other is StyleRange &&
      other.start == start &&
      other.end == end &&
      other.style == style &&
      other.priority == priority;

  @override
  int get hashCode => Object.hash(start, end, style, priority);

  @override
  String toString() => 'StyleRange($start, $end, priority: $priority)';
}

/// Builds a [TextSpan] tree from two independent layers of styling.
///
/// [exclusive] is a mutually-exclusive layer: where two ranges overlap only one
/// survives, chosen by `start`, then [StyleRange.priority], then longest-first.
/// This is how pattern colouring (mentions, hashtags) behaves — a character has
/// exactly one pattern colour.
///
/// [decorations] is an additive layer: *every* range covering a character is
/// merged on top of whatever the exclusive layer produced. This is how
/// spell-check squiggles and the IME composing underline behave — they decorate
/// text without replacing its colour.
///
/// Splitting at every range boundary (rather than resolving overlaps across both
/// layers) is what lets a misspelling inside a hashtag keep both the hashtag
/// colour and the squiggle.
TextSpan buildLayeredTextSpan({
  required String text,
  TextStyle? baseStyle,
  List<StyleRange> exclusive = const <StyleRange>[],
  List<StyleRange> decorations = const <StyleRange>[],
}) {
  if (text.isEmpty) return TextSpan(text: '', style: baseStyle);

  final resolvedExclusive = _resolveExclusive(_clamp(exclusive, text.length));
  final clampedDecorations = _clamp(decorations, text.length);

  if (resolvedExclusive.isEmpty && clampedDecorations.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }

  // Every boundary at which the effective style can change.
  final boundaries = <int>{0, text.length};
  for (final r in resolvedExclusive) {
    boundaries.add(r.start);
    boundaries.add(r.end);
  }
  for (final r in clampedDecorations) {
    boundaries.add(r.start);
    boundaries.add(r.end);
  }
  final cuts = boundaries.toList()..sort();

  final children = <InlineSpan>[];
  int? runStart;
  TextStyle? runStyle;

  void flush(int end) {
    if (runStart == null) return;
    children.add(TextSpan(text: text.substring(runStart!, end), style: runStyle));
    runStart = null;
  }

  for (int i = 0; i < cuts.length - 1; i++) {
    final sliceStart = cuts[i];
    final sliceEnd = cuts[i + 1];
    if (sliceStart >= sliceEnd) continue;

    TextStyle? style = baseStyle;
    for (final r in resolvedExclusive) {
      if (r.start <= sliceStart && r.end >= sliceEnd) {
        style = style?.merge(r.style) ?? r.style;
        break; // resolved layer is non-overlapping, so at most one applies
      }
    }
    for (final r in clampedDecorations) {
      if (r.start <= sliceStart && r.end >= sliceEnd) {
        style = style?.merge(r.style) ?? r.style;
      }
    }

    // Coalesce adjacent slices that ended up with the same style, so the tree
    // stays small and stable for golden tests.
    if (runStart != null && style == runStyle) continue;
    flush(sliceStart);
    runStart = sliceStart;
    runStyle = style;
  }
  flush(text.length);

  return TextSpan(style: baseStyle, children: children);
}

List<StyleRange> _clamp(List<StyleRange> ranges, int length) {
  final out = <StyleRange>[];
  for (final r in ranges) {
    final start = r.start.clamp(0, length);
    final end = r.end.clamp(0, length);
    if (start >= end) continue;
    out.add(StyleRange(start: start, end: end, style: r.style, priority: r.priority));
  }
  return out;
}

List<StyleRange> _resolveExclusive(List<StyleRange> ranges) {
  if (ranges.length < 2) return ranges;
  final sorted = [...ranges]..sort((a, b) {
    if (a.start != b.start) return a.start.compareTo(b.start);
    if (a.priority != b.priority) return a.priority.compareTo(b.priority);
    return (b.end - b.start) - (a.end - a.start);
  });
  final resolved = <StyleRange>[];
  int lastEnd = -1;
  for (final r in sorted) {
    if (r.start >= lastEnd) {
      resolved.add(r);
      lastEnd = r.end;
    }
  }
  return resolved;
}
