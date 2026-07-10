#!/usr/bin/env bash
# Pre-PR enforcement gate for Claude Code agents.
# Wired as a PreToolUse hook on the Bash tool (see .claude/settings.json).
# Reads the tool-call JSON on stdin, inspects `git commit` / `git push`
# commands and blocks (exit 2) on a rule breach. stderr is fed back to the
# agent so it can self-correct. Non-git commands pass straight through.
set -uo pipefail

payload="$(cat)"

extract_cmd() {
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$payload" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null
  elif command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null
  fi
}
CMD="$(extract_cmd)"
[ -z "${CMD:-}" ] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$ROOT" 2>/dev/null || exit 0

block() { echo "pre-PR gate blocked this command: $1" >&2; exit 2; }

# Act only on git commit / git push.
is_commit=0; is_push=0
printf '%s' "$CMD" | grep -qE '(^|[;&|`(]|[[:space:]])git[[:space:]]+commit' && is_commit=1
printf '%s' "$CMD" | grep -qE '(^|[;&|`(]|[[:space:]])git[[:space:]]+push'   && is_push=1
[ "$is_commit" -eq 0 ] && [ "$is_push" -eq 0 ] && exit 0

# --- Identity: never commit as Claude --------------------------------------
name="$(git config user.name 2>/dev/null || true)"
email="$(git config user.email 2>/dev/null || true)"
lname="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
printf '%s' "$lname" | grep -q 'claude' && \
  block "git user.name is '$name' -- commit as the current developer, never as Claude (git config user.name \"Your Name\")."
printf '%s' "$email" | grep -qi 'noreply@anthropic.com' && \
  block "git user.email is the Claude default ($email) -- set your developer email before committing."
printf '%s' "$CMD" | grep -qiE 'co-authored-by:.*claude' && \
  block "commit message contains a 'Co-Authored-By: ... Claude' line -- remove it."

# --- Default + current branch ----------------------------------------------
DEFAULT_BRANCH="$(grep -iE 'Default branch for this repo:' CLAUDE.md 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*//' | tr -d '[:space:]')"
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"
CUR_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

# --- Branch-name prefix rule -----------------------------------------------
if [ -n "$CUR_BRANCH" ] && [ "$CUR_BRANCH" != "$DEFAULT_BRANCH" ]; then
  printf '%s' "$CUR_BRANCH" | grep -qE '^[A-Za-z0-9._-]+/.+' || \
    block "branch '$CUR_BRANCH' must start with a developer prefix, e.g. 'ot/$CUR_BRANCH'."
fi

# Heavy checks run on push only, and only when Dart/pubspec actually changed.
[ "$is_push" -eq 0 ] && exit 0

changed="$( { git diff --name-only "origin/$DEFAULT_BRANCH"...HEAD; \
              git diff --name-only HEAD~1..HEAD; \
              git diff --name-only; git diff --name-only --cached; } 2>/dev/null )"
printf '%s' "$changed" | grep -qE '(^|/)(lib|test)/.*\.dart$|(^|/)pubspec\.yaml$' || exit 0

command -v flutter >/dev/null 2>&1 || \
  block "Flutter 3.35.7 is required to validate Dart changes before pushing, but 'flutter' is not on PATH."

dart format --output=none --set-exit-if-changed . >/dev/null 2>&1 || \
  block "code is not formatted -- run 'dart format .' and re-commit."
flutter analyze >/tmp/_ppr_analyze.log 2>&1 || \
  block "'flutter analyze' reported issues:$(printf '\n')$(tail -20 /tmp/_ppr_analyze.log)"

# --- Version-bump rule (vs the default branch) ------------------------------
strip() { sed -E 's/version:[[:space:]]*//; s/\+.*$//'; }
cur_ver="$(grep -E '^version:' pubspec.yaml 2>/dev/null | head -1 | strip | tr -d '[:space:]')"
base_ver="$(git show "origin/$DEFAULT_BRANCH:pubspec.yaml" 2>/dev/null | grep -E '^version:' | head -1 | strip | tr -d '[:space:]')"
if [ -n "$cur_ver" ] && [ -n "$base_ver" ]; then
  if [ "$cur_ver" = "$base_ver" ] || \
     [ "$(printf '%s\n%s\n' "$base_ver" "$cur_ver" | sort -V | tail -1)" != "$cur_ver" ]; then
    block "pubspec version ($cur_ver) must be higher than $DEFAULT_BRANCH ($base_ver) -- bump it."
  fi
fi

exit 0
