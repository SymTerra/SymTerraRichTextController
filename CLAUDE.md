# Project rules

## Environment
- ALWAYS use Flutter 3.35.7. Install or switch to it before any Flutter command.
- Default branch for this repo: main

## Git conventions
- Branch names MUST start with the current developer's prefix followed by `/` (e.g. `ot/fix-login-crash`).
- Determine the prefix from git identity: run `git config user.name`, take the lowercase initials (e.g. "Oscar Tigreros" -> `ot`). If user.name is empty or a single word, use the part of `git config user.email` before the `@`.
- If neither is set, STOP and ask for the prefix rather than guessing.
- Always branch off this repo's default branch.
- Commit as the current developer. Never author or co-author commits as Claude. Do NOT add a "Co-Authored-By: Claude" line.
- British English in all comments, docs and commit messages.

## Design system
- Text styles: always use the text styles defined in the core plugin. Do NOT create new text styles — reuse an existing one and override only its colour when a different colour is needed.
- Colours: only use the colours defined in the core plugin. Do NOT introduce new colours. If a genuinely new colour is strictly required, STOP and flag it to the designer rather than adding one.

## File naming and coverage
- The naming rule applies to views, models and cubit state files: view files end with `_view.dart`, Freezed model files end with `_model.dart`, and cubit state files end with `_state.dart`. Other file kinds follow the existing suffix conventions (`_widget`, `_cubit`, `_repository`, `_api`, …).
- Entities/models carry `// coverage:ignore-file` as the first line, unless they contain inner methods that should be tested.
- `state` files that accumulate real logic should be tested and excluded from the coverage-ignore list case by case, rather than ignoring the whole file.

## Versioning
- Bump the `pubspec.yaml` version semantically: the last digit for UI or minor, non-breaking changes; the middle digit for changes to a model, local database or endpoint (anything that could break older apps); the first digit for major conceptual or navigation changes.

## Before opening a PR
- Ensure the branch's `version` in `pubspec.yaml` is higher than the source (default) branch's version, where applicable. Bump it if not.
- Run the `pre-pr` skill and complete every step before opening the PR.
