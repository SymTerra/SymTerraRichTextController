import 'package:flutter/material.dart';

import 'src/layered_text_span.dart';
import 'src/spell_check_spans.dart';

export 'src/layered_text_span.dart';
export 'src/spell_check_spans.dart';

/// SymTerraRichTextController
/// =========================
///
/// A rich text controller for Flutter that supports:
/// - Pattern-based syntax highlighting (mentions, hashtags, URLs, etc.)
/// - Atomic tokens: typing or deleting inside a token removes the whole token
/// - Per-pattern delete callbacks and a global fallback
/// - ID-backed tokens for any pattern (e.g., mentions with stable IDs)
/// - Token insertion that can replace active handles (e.g., "@sa" → "@sarah_cro")
///
/// Usage:
///   - Define your patterns using [PatternStyle].
///   - Use [insertToken] to insert tokens at the caret or replace active handles.
///   - Listen for token deletions via per-pattern or global callbacks.
///   - Access ID-backed tokens via [idTokens].
///
/// See individual class and method documentation for details.setState(() {});
/// Payload describing a removed token.
class DeletedToken {
  /// The removed substring, e.g. "@sarah_cro"
  final String text;

  /// Pattern key: "mention", "hashtag", etc.
  final String key;

  /// The regex for this pattern.
  final RegExp pattern;

  /// Start index in OLD text.
  final int start;

  /// End index (exclusive) in OLD text.
  final int end;

  /// Your stable ID if present.
  final String? tokenId;
  const DeletedToken({
    required this.text,
    required this.key,
    required this.pattern,
    required this.start,
    required this.end,
    this.tokenId,
  });
}

/// Defines how a pattern looks, behaves, and is recognized in the text.
class PatternStyle {
  /// Unique key for the pattern (e.g. "mention", "hashtag", "url").
  final String key;

  /// Regex used to recognize the pattern in text.
  final RegExp pattern;

  /// Text style for rendering matched tokens.
  final TextStyle style;

  /// Optional trigger character (e.g. "@", "#") for handle replacement.
  final String? trigger;

  /// Optional callback invoked when a token of this pattern is deleted.
  final void Function(DeletedToken tok)? onDeleted;

  const PatternStyle({required this.key, required this.pattern, required this.style, this.trigger, this.onDeleted});
}

/// Internal record for any ID-backed token in the editor.
class IdBackedToken {
  /// Start and end indices of the token in the text ([start, end)).
  int start, end;

  /// Pattern key for this token.
  final String key;

  /// Stable ID from your data model.
  final String id;

  /// Display label (e.g., "sarah_cro").
  final String label;
  IdBackedToken({required this.start, required this.end, required this.key, required this.id, required this.label});
}

/// Internal token representation for pattern matches and ID-backed tokens.
class _Token {
  final int start, end, priority;
  final PatternStyle style;
  String? tokenId; // Set when matched with an id-backed token
  _Token({required this.start, required this.end, required this.style, required this.priority});

  /// Returns true if this token overlaps the given range [s, e).
  bool overlaps(int s, int e) => s < end && e > start;
}

/// Simple range representation.
class _Range {
  final int start, end;
  const _Range(this.start, this.end);
}

///
/// SymTerraRichTextController
/// --------------------------
///
/// A [TextEditingController] that supports pattern-based highlighting and atomic tokens.
/// See class-level documentation above for features.
///
class SymTerraRichTextController extends TextEditingController with SpellCheckSpans {
  /// Creates a rich text controller with the given [patterns] and optional [onAnyDeleted] callback.
  ///
  /// [patterns] are used for highlighting and token recognition.
  /// [onAnyDeleted] is called when a token is deleted and no per-pattern callback is provided.
  SymTerraRichTextController({required this.patterns, this.onAnyDeleted, super.text}) {
    _lastValue = value;
  }

  /// Patterns in precedence order (earlier wins on overlap).
  final List<PatternStyle> patterns;

  /// Optional fallback when a pattern doesn't provide an onDeleted callback.
  final void Function(DeletedToken tok)? onAnyDeleted;

  bool _applyingEdit = false;
  late TextEditingValue _lastValue;

  /// Registry of ID-backed tokens (for *any* pattern).
  final List<IdBackedToken> _idTokens = [];

  /// Unmodifiable view of ID-backed tokens.
  List<IdBackedToken> get idTokens => List.unmodifiable(_idTokens);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Inserts a token for [patternKey] at the caret or replaces the active handle.
  ///
  /// If the pattern defines a [trigger] (e.g., "@"), this will replace the active
  /// handle the user is typing (like "@sa" -> "@sarah_cro"). Otherwise it inserts
  /// at the caret.
  ///
  /// - [visibleText] is what appears in the editor (e.g., "@sarah_cro", "#Roadmap_42").
  /// - [tokenId] optionally binds a stable ID to this token (useful for mentions etc.).
  /// - [label] is an optional human label (defaults to [visibleText]).
  void insertToken({required String patternKey, required String visibleText, String? tokenId, String? label}) {
    final ps = patterns.firstWhere(
      (p) => p.key == patternKey,
      orElse: () => throw ArgumentError('Pattern key not found: $patternKey'),
    );

    final caret = selection.baseOffset.clamp(0, text.length);
    final active = (ps.trigger != null) ? _activeHandleAtFor(text, caret, ps.trigger!) : null;

    final replaceStart = active?.start ?? caret;
    final replaceEnd = active?.end ?? caret;

    final before = text.substring(0, replaceStart);
    final after = text.substring(replaceEnd);
    final newText = '$before$visibleText$after';

    // Remove any id-backed tokens fully within the replaced slice, then shift those after it.
    _removeIdTokensInRange(replaceStart, replaceEnd);
    final delta = visibleText.length - (replaceEnd - replaceStart);
    _shiftIdTokens(replaceEnd, delta);

    final start = replaceStart;
    final end = replaceStart + visibleText.length;

    if (tokenId != null) {
      _idTokens.add(IdBackedToken(start: start, end: end, key: ps.key, id: tokenId, label: label ?? visibleText));
    }

    _apply(
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: end),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Core edit interception (ATOMIC)
  // ---------------------------------------------------------------------------

  /// Intercepts edits to enforce atomic token behavior.
  /// - Insertion inside a token replaces the whole token.
  /// - Deletion inside a token removes the whole token.
  @override
  set value(TextEditingValue newValue) {
    if (_applyingEdit) {
      _lastValue = newValue;
      super.value = newValue;
      return;
    }

    final oldValue = _lastValue;
    final oldText = oldValue.text;
    final newText = newValue.text;

    final isDeletion = newText.length < oldText.length;
    final isInsertion = newText.length > oldText.length;

    // Build tokens from OLD text (authoritative for interception).
    final tokens = _collectTokens(oldText); // sorted, non-overlapping

    // ---------------- Insertions ----------------
    if (isInsertion && oldValue.selection.isValid && newValue.selection.isValid) {
      final i = oldValue.selection.baseOffset.clamp(0, oldText.length);
      final delta = newText.length - oldText.length; // could be >1 for paste
      final inserted = (i + delta <= newText.length && delta > 0) ? newText.substring(i, i + delta) : '';

      // ATOMIC: if the caret is inside a token, replace the WHOLE token with the inserted text.
      final token = _tokenContaining(tokens, i);
      if (token != null) {
        final removed = oldText.substring(token.start, token.end);
        final updated = oldText.replaceRange(token.start, token.end, inserted);
        final caret = token.start + inserted.length;

        // Update ID-backed tokens: remove the old token, then shift everything after.
        _removeIdTokensInRange(token.start, token.end);
        _shiftIdTokens(token.end, -(token.end - token.start));
        _shiftIdTokens(token.start, inserted.length);

        _emitPatternDeleted(token, removed);

        _apply(
          TextEditingValue(
            text: updated,
            selection: TextSelection.collapsed(offset: caret),
          ),
        );
        return;
      }

      // Insertion outside tokens: shift IDs to the right.
      _shiftIdTokens(i, delta);
      _lastValue = newValue;
      super.value = newValue;
      return;
    }

    // ---------------- Deletions ----------------
    if (isDeletion && oldValue.selection.isValid && newValue.selection.isValid) {
      // Derive deleted range from selection delta.
      int delStart, delEnd;
      final oldBase = oldValue.selection.baseOffset;
      final oldExtent = oldValue.selection.extentOffset;
      final newBase = newValue.selection.baseOffset;

      if (!oldValue.selection.isCollapsed) {
        delStart = oldBase < oldExtent ? oldBase : oldExtent;
        delEnd = oldBase > oldExtent ? oldBase : oldExtent;
      } else {
        if (newBase == oldBase - 1) {
          // Backspace
          delStart = newBase;
          delEnd = oldBase;
        } else {
          // Forward-delete (or platform-specific)
          delStart = oldBase;
          delEnd = oldBase + 1;
        }
      }
      delStart = delStart.clamp(0, oldText.length);
      delEnd = delEnd.clamp(delStart, oldText.length);

      // ATOMIC: remove ALL tokens overlapped by the deletion range.
      final overlapped = tokens.where((t) => t.overlaps(delStart, delEnd)).toList();
      if (overlapped.isEmpty) {
        // Regular deletion outside tokens: shift IDs left.
        final delta = newText.length - oldText.length; // negative
        _shiftIdTokens(delStart, delta);
        _lastValue = newValue;
        super.value = newValue;
        return;
      }

      // Remove overlapped tokens left→right in a single pass.
      int shift = 0;
      String updated = oldText;
      int caret = delStart;
      for (final t in overlapped) {
        final s = t.start + shift;
        final e = t.end + shift;
        final removed = updated.substring(s, e);
        updated = updated.replaceRange(s, e, '');
        shift -= (e - s);
        caret = s;

        _removeIdTokensInRange(t.start, t.end);
        _shiftIdTokens(t.end, -(t.end - t.start));

        _emitPatternDeleted(t, removed);
      }

      _apply(
        TextEditingValue(
          text: updated,
          selection: TextSelection.collapsed(offset: caret.clamp(0, updated.length)),
        ),
      );
      return;
    }

    // Selection moves / no size change — just apply.
    _lastValue = newValue;
    super.value = newValue;
  }

  // ---------------------------------------------------------------------------
  // Rendering (syntax highlighting)
  // ---------------------------------------------------------------------------

  /// Builds the [TextSpan] tree for rendering.
  ///
  /// Pattern matches form the *exclusive* colour layer; spell-check squiggles and
  /// the IME composing underline are merged on top as a decoration layer, so a
  /// misspelling inside a hashtag keeps both the hashtag colour and the squiggle.
  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, bool withComposing = false}) {
    final t = value.text;
    if (t.isEmpty) return TextSpan(text: '', style: style);

    final exclusive = <StyleRange>[];
    for (int i = 0; i < patterns.length; i++) {
      final ps = patterns[i];
      for (final m in ps.pattern.allMatches(t)) {
        exclusive.add(StyleRange(start: m.start, end: m.end, style: ps.style, priority: i));
      }
    }

    return buildSpellCheckedSpan(
      text: t,
      baseStyle: style,
      exclusive: exclusive,
      withComposing: withComposing,
    );
  }

  /// Replaces `[start, end)` with [replacement], keeping token bookkeeping intact.
  ///
  /// Assigning to `text` would leave [idTokens] offsets stale and silently break
  /// mention IDs, so suggestion replacement must come through here. Any token
  /// whose text the replacement disturbs is reported through the usual delete
  /// callbacks so the app can drop it from its own state.
  @override
  void replaceRange(int start, int end, String replacement) {
    final t = text;
    final from = start.clamp(0, t.length);
    final to = end.clamp(from, t.length);
    if (from == to && replacement.isEmpty) return;

    for (final tok in _collectTokens(t)) {
      if (tok.overlaps(from, to)) {
        _emitPatternDeleted(tok, t.substring(tok.start, tok.end));
      }
    }

    final updated = t.replaceRange(from, to, replacement);
    _idTokens.removeWhere((tok) => tok.start < to && tok.end > from);
    _shiftIdTokens(to, replacement.length - (to - from));

    _apply(
      TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: from + replacement.length),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Applies the given [TextEditingValue] and updates internal state.
  void _apply(TextEditingValue v) {
    _applyingEdit = true;
    try {
      _lastValue = v;
      super.value = v;
    } finally {
      _applyingEdit = false;
    }
  }

  /// Collects all tokens (pattern matches and ID-backed) from [source] text.
  List<_Token> _collectTokens(String source) {
    final tmp = <_Token>[];

    // 1) Regex-derived tokens (normal)
    for (int pIndex = 0; pIndex < patterns.length; pIndex++) {
      final ps = patterns[pIndex];
      for (final m in ps.pattern.allMatches(source)) {
        tmp.add(
          _Token(
            start: m.start,
            end: m.end,
            style: ps,
            priority: pIndex, // larger (worse) than ID-backed tokens
          ),
        );
      }
    }

    // 2) ID-backed tokens (authoritative) — insert with *higher precedence*
    //    Use a priority lower than any pattern index so they always win on overlap.
    const int idPriority = -999999;
    for (final idt in _idTokens) {
      final ps = patterns.firstWhere(
        (p) => p.key == idt.key,
        orElse: () => throw StateError('No PatternStyle for key: ${idt.key}'),
      );
      tmp.add(_Token(start: idt.start, end: idt.end, style: ps, priority: idPriority)..tokenId = idt.id);
    }

    if (tmp.isEmpty) return const [];

    // 3) Sort: by start, then priority (lower is *higher* precedence), then longer-first
    tmp.sort((a, b) {
      if (a.start != b.start) return a.start.compareTo(b.start);
      if (a.priority != b.priority) return a.priority.compareTo(b.priority);
      return (b.end - b.start) - (a.end - a.start);
    });

    // 4) Resolve overlaps by keeping the first (highest-precedence) token
    final resolved = <_Token>[];
    int lastEnd = -1;
    for (final t in tmp) {
      if (t.start >= lastEnd) {
        resolved.add(t);
        lastEnd = t.end;
      }
    }

    return resolved;
  }

  /// Returns the token containing index [i], or null if none.
  _Token? _tokenContaining(List<_Token> tokens, int i) {
    for (final t in tokens) {
      if (i >= t.start && i < t.end) return t;
    }
    return null;
  }

  /// Shifts all ID-backed tokens at or after [pivot] by [delta] characters.
  void _shiftIdTokens(int pivot, int delta) {
    if (delta == 0) return;
    for (final t in _idTokens) {
      if (t.start >= pivot) {
        t.start += delta;
        t.end += delta;
      }
    }
  }

  /// Removes all ID-backed tokens fully within [start, end).
  void _removeIdTokensInRange(int start, int end) {
    _idTokens.removeWhere((t) => t.start >= start && t.end <= end);
  }

  /// Detects the active handle for a specific [trigger] (e.g., '@' or '#') at/around the caret.
  /// Returns a [_Range] if a handle is found, otherwise null.
  _Range? _activeHandleAtFor(String t, int caret, String trigger) {
    final wordChar = RegExp(r'[A-Za-z0-9_]');
    // Expand left to the beginning of the current [A-Za-z0-9_] run.
    int left = caret.clamp(0, t.length);
    while (left > 0 && wordChar.hasMatch(t[left - 1])) {
      left--;
    }
    if (left > 0 && t[left - 1] == trigger) {
      final atPos = left - 1;
      if (atPos == 0 || !wordChar.hasMatch(t[atPos - 1])) {
        // Expand right to consume the rest of the handle
        int right = caret;
        while (right < t.length && wordChar.hasMatch(t[right])) {
          right++;
        }
        return _Range(atPos, right);
      }
    }
    // If caret is somewhere inside a handle, expand back to the trigger
    int i = caret - 1;
    while (i >= 0 && wordChar.hasMatch(t[i])) {
      i--;
    }
    if (i >= 0 && t[i] == trigger) {
      final atPos = i;
      if (atPos == 0 || !wordChar.hasMatch(t[atPos - 1])) {
        int right = caret;
        while (right < t.length && wordChar.hasMatch(t[right])) {
          right++;
        }
        return _Range(atPos, right);
      }
    }
    return null;
  }

  /// Emits a [DeletedToken] payload for the given token and removed text.
  /// Invokes per-pattern or global delete callback.
  void _emitPatternDeleted(_Token t, String removed) {
    final payload = DeletedToken(
      text: removed,
      key: t.style.key,
      pattern: t.style.pattern,
      start: t.start,
      end: t.end,
      tokenId: t.tokenId,
    );
    if (t.style.onDeleted != null) {
      t.style.onDeleted!(payload);
    } else {
      onAnyDeleted?.call(payload);
    }
  }
}
