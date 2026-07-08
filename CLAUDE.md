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

## Before opening a PR
- Ensure the branch's `version` in `pubspec.yaml` is higher than the source (default) branch's version, where applicable. Bump it if not.
- Run the `pre-pr` skill and complete every step before opening the PR.
