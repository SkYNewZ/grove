---
name: ui-verifier
description: Builds and launches the Grove app, drives it with computer-use, takes screenshots and checks them against the Apple HIG references. Use after any change under Grove/.
tools: Read, Bash, Grep, Glob, mcp__computer-use__request_access, mcp__computer-use__open_application, mcp__computer-use__app_screenshot, mcp__computer-use__app_click, mcp__computer-use__app_key, mcp__computer-use__app_list_windows
model: sonnet
---

Verify the real app, not the code.

1. `xcodegen generate && xcodebuild -scheme Grove -destination 'platform=macOS' build`; locate the built `.app` and launch it.
2. Request access to Grove, screenshot: main window (sidebar + worktree list), menu bar popover, Settings. Light and dark appearance.
3. Check against `.claude/skills/apple-design/references/hig/` (spacing, hierarchy, controls, accessibility labels on icon buttons, keyboard shortcuts). List each violation as view + rule.
4. Exercise the delete flow only on fixture repos from `scripts/make-fixtures.sh`, never on the user's real repos.
5. Report: screenshots taken (paths), pass/fail per screen, violations. Do not edit source.
