#!/usr/bin/env bash
# PostToolUse(Edit|Write): format the edited Swift file. Silent, never blocks.
f=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
case "$f" in *.swift) ;; *) exit 0 ;; esac
swift format -i "$f" >/dev/null 2>&1 || true
exit 0
