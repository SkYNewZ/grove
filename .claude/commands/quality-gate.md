---
description: End-of-task quality gate — script for the mechanical checks, then /simplify, ponytail review, and independent review when sensitive
allowed-tools: Bash, Read, Edit
---

Run the gate and report real output. Never claim success without it. Stop and surface any failure instead of pushing past it.

1. **Mechanical checks.** Run `scripts/quality-gate.sh`. It runs format lint, build and unit tests when Swift changed, the app build when `Grove/` changed, and prints `SENSITIVE` when removal/git code changed. Exit code 0 = pass. Fix failures (the script is the source of truth), rerun until it passes.
2. **`/simplify`** when the diff has Swift code. Skip for docs/config only. Rerun step 1 after it applies fixes.
3. **`/ponytail:ponytail-review`** on the diff. Apply the findings that are real, rerun step 1.
4. **Independent review when the script printed `SENSITIVE`:** launch the `swift-reviewer` agent on the diff. Brief it to report data-loss and correctness gaps only, not style.
5. **UI changes (`Grove/` touched):** launch the `ui-verifier` agent for screenshots against the HIG.

End with a pass/fail line per step that ran, and the steps skipped with the reason. Then commit on `main` (conventional commit, no push).
