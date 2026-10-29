---
paths:
  - "**/*.swift"
---

# Style et nommage Swift

- Swift 6, concurrence stricte. `actor` pour l'état partagé, `@MainActor` pour l'UI, `Sendable` explicite. Pas de `DispatchQueue`, pas de `@unchecked Sendable` sans commentaire justifiant.
- `@Observable` (Observation), jamais `ObservableObject`. SwiftUI : état local en `@State`, modèle partagé via `@Environment`.
- Nommage : types en UpperCamelCase, fonctions/variables en lowerCamelCase, noms lisibles à l'appel (guidelines API Swift). Un type par fichier, fichier = nom du type. Booléens en `is/has/can`.
- Dossiers de `GroveKit` = un domaine (`Discovery`, `Git`, `Removal`, `Sizing`, `Hosting`, `Launch`, `Naming`, `Environment`). Un domaine ne dépend que de `Git` et `Environment`.
- Sous-process : une seule porte (`ProcessRunner`), arguments en tableau (jamais de chaîne shell), cwd explicite, code de sortie vérifié, PATH résolu via `ToolLocator`.
- Pas de `try!`, `fatalError`, `!` sur des données externes. Erreurs typées par domaine ; message utilisateur en français, jamais de sortie brute git.
- Commentaire seulement pour le pourquoi. Pas d'abstraction sans deuxième usage.
- Format : `swift format` (config `.swift-format`), appliqué par hook.
- UI : suivre `.claude/skills/apple-design/references/hig/` ; composants SwiftUI natifs d'abord ; labels d'accessibilité sur chaque bouton icône ; clair/sombre.
- Tests : Swift Testing (`@Test`, `#expect`), nom = comportement (`removesMergedWorktreeKeepingBackupRef`). Repos git temporaires, jamais les vrais repos de l'utilisateur.

## Pièges constatés (chaque erreur corrigée devient une règle)

- `MenuBarExtra(.window)` : un `ScrollView` n'a pas de hauteur propre et s'écrase à 0. Mesurer le contenu (`onGeometryChange`) et fixer `.frame(height: min(contenu, max))`.
- `HStack(alignment: .firstTextBaseline)` avec un glyphe `Shape` (sans ligne de base) le décale vers le haut : aligner en `.top`/`.center` et donner le même cadre (24×22) à tous les boutons icône.
- Un `.command` ouvert dans Warp contourne la configuration du shell de l'utilisateur : ouvrir un dossier ou une URL `warp://` plutôt qu'un script.
- Un popover qui doit rester sans défilement : pas de `ScrollView`, `.fixedSize(horizontal: false, vertical: true)` sur le texte.
