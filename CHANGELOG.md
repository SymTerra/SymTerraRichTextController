## 0.0.2

* Add a spell-check decoration layer so misspellings and pattern colours can coexist.
  * `buildLayeredTextSpan` splits text at every range boundary and merges an additive
    decoration layer over the mutually-exclusive pattern layer. Previously overlapping
    spans were resolved by dropping one, so a typo inside a hashtag lost a style.
  * `SpellCheckSpans` mixin: `setMisspelledRanges` (no-ops when unchanged, to avoid
    rebuild loops), `misspelledStyle`, and the shared span builder.
  * `replaceRange` keeps `idTokens` offsets correct and reports disturbed tokens through
    the existing delete callbacks — assigning to `text` left mention IDs stale.
  * `SpellCheckableTextEditingController` for plain fields that need squiggles only.
  * `buildTextSpan` now honours `withComposing`, which was previously ignored.

## 0.0.1

* TODO: Describe initial release.
