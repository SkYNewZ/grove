#!/usr/bin/env bash
# Deterministic part of /quality-gate: format lint, build, unit tests, app build.
# Usage: scripts/quality-gate.sh        Exit 0 = every step that ran passed.
# Scope = files changed since HEAD (staged, unstaged, untracked); everything on the first commit.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2

if git rev-parse --verify -q HEAD >/dev/null; then
  files=$({ git diff --name-only HEAD; git ls-files -o --exclude-standard; } | sort -u)
else
  files=$(git ls-files -o -c --exclude-standard | sort -u)
fi
[ -n "$files" ] || { echo "SKIP no changed files"; exit 0; }

swift_files=$(printf '%s\n' "$files" | grep -E '\.swift$' | while read -r f; do [ -f "$f" ] && echo "$f"; done)
sensitive=$(printf '%s\n' "$files" | grep -E 'GroveKit/(Sources|Tests)/GroveKit(Tests)?/(Removal|Git)/|Package.swift' || true)
app_touched=$(printf '%s\n' "$files" | grep -E '^(Grove/|project\.yml)' || true)
pkg=Packages/GroveKit

fail=0
run() { # name, command...
  local name="$1"; shift
  local log; log=$(mktemp)
  if "$@" >"$log" 2>&1; then echo "PASS $name"; else echo "FAIL $name"; tail -n 25 "$log"; fail=1; fi
  rm -f "$log"
}

if [ -n "$swift_files" ]; then
  # shellcheck disable=SC2086
  run format-lint swift format lint --strict $swift_files
else
  echo "SKIP format-lint (no Swift in the diff)"
fi

if [ -n "$swift_files" ] && [ -f "$pkg/Package.swift" ]; then
  run build swift build --package-path "$pkg"
  run unit-tests swift test --package-path "$pkg"
else
  echo "SKIP build, unit-tests (no Swift change or no $pkg yet)"
fi

if [ -n "$app_touched" ] && [ -f project.yml ]; then
  run app-build sh -c 'xcodegen generate --quiet && xcodebuild -scheme Grove -destination "platform=macOS" -quiet build'
else
  echo "SKIP app-build (app untouched)"
fi

[ -z "$sensitive" ] || echo "SENSITIVE removal/git paths touched: add an independent review (swift-reviewer)"
[ "$fail" -eq 0 ] && echo "GATE PASS" || echo "GATE FAIL"
exit "$fail"
