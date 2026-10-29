# Contributing

Issues and pull requests are welcome.

1. Fork the repo and branch from `main`.
2. Make your change, with a test when it touches logic (`Packages/GroveKit`, Swift Testing on temporary git repos).
3. Run the checks:

   ```bash
   swift format lint --strict -r Packages Grove
   swift test --package-path Packages/GroveKit
   ```

4. Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`…) and open a pull request against `main`.

Changes under `Packages/GroveKit/Sources/GroveKit/Removal/` or `Git/` must never lose a commit or a file when a worktree is removed: keep the backup ref, the Trash and the refusal of locked, unmerged and unique detached states.

Build the app with `DEVELOPMENT_TEAM=<your team id> scripts/build-app.sh` (requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen)).
