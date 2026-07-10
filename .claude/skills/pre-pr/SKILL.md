---
name: pre-pr
description: Run before opening any pull request in this Flutter repo. Use when the user says "open a PR", "raise a PR", "run pre-PR", or is about to push a branch for review. Enforces locale extraction, comment removal, analyze, format, tests, and branch/commit conventions.
---

# Pre-PR checklist

Run every step in order. Do not open the PR until all pass.

1. Confirm Flutter 3.35.7 is active. Install or switch if not.
2. Move all hard-coded UI strings into the locale files. No raw string literals left in widgets.
3. Remove redundant comments and commented-out code — in particular the narration comments an AI agent tends to leave behind that merely restate what the code does (e.g. `// loop through items`). Keep comments that explain *why*, and the required markers (`TODO(api)`, `coverage:ignore*`, Firestore-swap markers).
4. Run `flutter analyze` and fix all warnings.
5. Run `dart format .`.
6. Add or update unit tests for every cubit or repository you added or changed, then run the relevant tests and confirm they pass.
7. Ensure the `version` in `pubspec.yaml` is higher than the source (default) branch's version, where applicable. Bump it if not.
8. Ensure the branch name starts with the developer's prefix (derived from git identity). Rename if not.
9. When committing, commit as the current developer. Never add a "Co-Authored-By: Claude" line.
10. Only after all the above, open the PR against the default branch.
