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

## Before opening a PR
- Run the `pre-pr` skill and complete every step before opening the PR.
