# CLAUDE.md

Grove : app macOS native (SwiftUI, macOS 26 uniquement) qui liste les worktrees git de plusieurs repos, indique lesquels peuvent être supprimés, et lance terminal / Claude Code / PR-MR en un clic.
## Commandes

```bash
swift test --package-path Packages/GroveKit   # tests de la logique métier
swift build --package-path Packages/GroveKit
swift format lint --strict -r Packages Grove  # lint ; `swift format -i -r …` pour corriger
xcodegen && xcodebuild -scheme Grove build    # app (quand project.yml existe)
scripts/quality-gate.sh                       # porte mécanique, code de sortie 0 = OK
```

## Architecture

- `Packages/GroveKit/` : toute la logique (scan, git, suppression, tailles, forges, lancement). Aucune dépendance à SwiftUI/AppKit sauf `Launch/`. Testée avec Swift Testing sur des repos git temporaires.
- `Grove/` : app SwiftUI fine (vues + `AppModel` `@Observable`). Aucune logique git ici.
- `scripts/` : porte qualité, fixtures, bench, hooks git.
- Concurrence Swift 6 stricte : un `actor` par repo pour git et tailles, UI en `@MainActor`. Pas de dépendance externe sans accord.
- Détails : `.claude/rules/` (chargées selon les fichiers touchés).

## Invariants anti-perte (non négociables)

Supprimer un worktree ne doit jamais perdre un commit ni un fichier (incident réel : HEAD détaché perdu). Toute modification de `Removal/` ou `Git/` doit garder : backup ref `refs/grove-backup/*` avant toute suppression, Corbeille (jamais `rm`), `git branch -d` (jamais `-D`), refus des états locked / non mergé / détaché unique. Voir `.claude/rules/removal-safety.md`.

## Distribution

Build local signé (`DEVELOPMENT_TEAM=<id équipe> scripts/build-app.sh`). La notarisation (`scripts/notarize.sh`, non testé) exige l'adhésion payante Apple Developer Program et un certificat Developer ID : impossible tant que le compte est gratuit.

## Boucle de développement

Pour chaque développement : implémenter → `/quality-gate` (script, puis `/simplify`, `/ponytail:ponytail-review`, et `swift-reviewer` si `SENSITIVE`) → commit sur `main`. Preuve par commande (tests, mesure, capture), jamais par jugement.

## Git

Trunk-based : tout sur `main` (ceci remplace le gitflow global). Commits conventionnels petits et fréquents.

## Langue

Code, commentaires, identifiants, messages de commit en anglais ; README en anglais ; docs utilisateur et ADR en français ; textes d'interface en français.

## Règles de maintenance

- Chaque erreur corrigée devient une règle dans `.claude/rules/` (et on retire celles devenues inutiles).
- `.claude/skills/apple-design/` est installé en local, non suivi par git (verrou `skills-lock.json`) : ne pas le modifier. Références HIG dans `references/hig/` pour toute décision d'UI.
- Garder ce fichier court ; le détail va dans `.claude/rules/`.
