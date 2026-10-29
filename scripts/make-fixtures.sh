#!/usr/bin/env bash
# Throwaway repos covering every worktree state, for checking the app (and its delete flow) safely.
# Usage: scripts/make-fixtures.sh [dir]   (default /tmp/grove-fixtures; recreated each run)
# Then: open -n build/Build/Products/Debug/Grove.app --args -scanRoots "(<dir>/src)"
set -euo pipefail
root="${1:-/tmp/grove-fixtures}"
rm -rf "$root"; mkdir -p "$root/src"
cd "$root/src"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

git init -q --bare -b main "$root/origin.git"
git init -q -b main demo-app
cd demo-app
printf '# Demo App\n\nFixture repo for Grove.\n' > README.md
echo ".env" > .gitignore
git add -A && git commit -q -m "init"
git remote add origin "git@github.com:example/demo-app.git"
git remote set-url --push origin "$root/origin.git"
git push -q "$root/origin.git" main
git fetch -q "$root/origin.git" main:refs/remotes/origin/main
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

wt() { git worktree add -q "$@"; }
wt -b merged-feature "$root/src/demo-app/.claude/worktrees/merged-feature" main
wt -b wip-feature "$root/src/demo-app/.claude/worktrees/wip-feature" main
echo "unsaved notes" > "$root/src/demo-app/.claude/worktrees/wip-feature/notes.txt"
echo "SECRET=1" > "$root/src/demo-app/.claude/worktrees/wip-feature/.env"
wt -b unmerged-feature "$root/src/demo-app/.claude/worktrees/unmerged-feature" main
git -C "$root/src/demo-app/.claude/worktrees/unmerged-feature" commit -q --allow-empty -m "work in progress"
wt --detach "$root/src/demo-app/.claude/worktrees/orphan-detached" main
git -C "$root/src/demo-app/.claude/worktrees/orphan-detached" commit -q --allow-empty -m "only commit, no branch"
wt -b locked-feature "$root/src/demo-app/.claude/worktrees/locked-feature" main
git worktree lock --reason "usb disk" "$root/src/demo-app/.claude/worktrees/locked-feature"
wt -b gone-feature "$root/src/demo-app/.claude/worktrees/gone-feature" main
rm -rf "$root/src/demo-app/.claude/worktrees/gone-feature"
echo "fixtures ready: $root/src"
