#!/usr/bin/env bash
# Stop: if Swift changed since HEAD, build and test before Claude may stop. Exit 2 = keep working.
input=$(cat)
[ "$(jq -r '.stop_hook_active // false' <<<"$input")" = "true" ] && exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
[ -f Packages/GroveKit/Package.swift ] || exit 0
if git rev-parse --verify -q HEAD >/dev/null; then
  changed=$({ git diff --name-only HEAD; git ls-files -o --exclude-standard; } | grep -E '\.swift$' || true)
else
  changed=$(git ls-files -o -c --exclude-standard | grep -E '\.swift$' || true)
fi
[ -n "$changed" ] || exit 0
out=$({ swift build --package-path Packages/GroveKit && swift test --package-path Packages/GroveKit; } 2>&1) && exit 0
printf 'Build or tests fail, fix before stopping:\n%s\n' "$(tail -n 30 <<<"$out")" >&2
exit 2
