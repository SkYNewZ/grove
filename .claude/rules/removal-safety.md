---
paths:
  - "Packages/GroveKit/Sources/GroveKit/Removal/**"
  - "Packages/GroveKit/Sources/GroveKit/Git/**"
  - "Packages/GroveKit/Tests/**"
---

# Suppression sûre d'un worktree

Pipeline unique dans `SafeRemover`, aucun autre chemin de suppression.

1. `git fetch --prune` uniquement ici (jamais pendant un scan).
2. Poser `refs/grove-backup/<nom>-<timestamp>` → HEAD, toujours, même si mergé.
3. Refuser (raison affichée) : worktree principal, `locked`, non mergé (squash-merge probable : le dire), HEAD détaché dont un commit n'est dans aucune autre ref que le backup.
4. WIP : confirmation forte listant les fichiers modifiés et les fichiers ignorés (`.env`…).
5. Avertir si un processus (`claude`…) a son cwd dans le worktree (`lsof -d cwd`).
6. `FileManager.trashItem` puis `git worktree prune`, puis `git branch -d`.

À livrer avec `SafeRemover` (revue indépendante de GroveKit/Git) :
- `WorktreeStatus.merged` ignore les fichiers ignorés (`.env`) et les modifs masquées (`update-index --assume-unchanged`, `skip-worktree`). Les lister avant confirmation (`git status --ignored`, `git ls-files -v`) ; la Corbeille les garde de toute façon.
- Un `reset --hard` laisse des commits uniquement dans les reflogs (`.git/worktrees/<nom>/logs/HEAD`, reflog de branche) que `worktree prune` + `branch -d` effacent : poser aussi un backup ref sur ces tips (`git rev-list -g`).
- Re-calculer le statut juste avant de supprimer (après le fetch), jamais sur un statut mis en cache par l'UI. Pas de timeout git pour l'instant (hook fsmonitor lent) : à ajouter.

Parser `git worktree list --porcelain -z`. Un worktree `prunable` (dossier absent) ne se prune qu'après le backup ref.

Tout changement ici exige un test d'invariant : chaque commit atteignable avant l'est après ; chaque fichier se retrouve dans la Corbeille. Fixtures : `scripts/make-fixtures.sh`.
