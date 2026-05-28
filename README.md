# PasteGlide

PasteGlide est un gestionnaire de presse-papier macOS natif écrit en Swift/AppKit. Il surveille le presse-papier, conserve un historique local dans SQLite, puis affiche les éléments copiés sous forme de cartes horizontales juste au-dessus du Dock.

## Raccourci clavier

La combinaison de touche pour appeler PasteGlide est:

```text
Option + Commande + V
⌥⌘V
```

Ce raccourci affiche ou masque le panneau d'historique.

## Prérequis

- macOS 14 ou plus récent
- Swift 6 ou plus récent
- Xcode Command Line Tools
- SQLite système, lié via `libsqlite3`
- Vision.framework système pour l'OCR des images

## Lancement

Depuis le dossier du projet:

```bash
swift run
```

PasteGlide démarre en mode accessoire:

- aucune fenêtre principale n'est ouverte au lancement
- une entrée `PasteGlide` apparaît dans la barre de menus
- le raccourci `⌥⌘V` ouvre ou ferme l'historique

## Utilisation

1. Lance PasteGlide avec `swift run`.
2. Copie du texte, un lien YouTube, une suite de chiffres, un mot de passe ou une image.
3. Appuie sur `⌥⌘V` pour afficher l'historique.
4. Utilise le champ de recherche pour filtrer les cartes par type, aperçu ou contenu.
5. Clique sur une carte pour remettre son contenu dans le presse-papier.
6. Pour une carte de mot de passe, fais un clic droit sur la carte pour révéler ou masquer le contenu localement.

Le panneau se ferme automatiquement après la sélection d'une carte.

Sur les cartes de texte, le badge de gauche affiche le nombre de caractères et les premiers mots quand ils tiennent dans l'espace disponible. Survole une carte pour afficher le contenu complet dans une bulle flottante lisible.

Le clavier permet aussi de piloter l'historique:

- Flèche gauche/droite: sélectionner la carte précédente ou suivante
- Entrée: copier la carte sélectionnée
- Suppr: supprimer la carte sélectionnée
- Échap: fermer le panneau

Un clic droit sur une carte permet de l'épingler ou de la supprimer. Les cartes épinglées restent en tête et ne sont pas supprimées par la rétention automatique.

## Types de cartes

PasteGlide classe automatiquement les contenus copiés:

- Rouge: lien YouTube
- Jaune: texte standard
- Violet: mot de passe probable, masqué par défaut
- Bleu: suite de chiffres
- Vert: image

Les cartes image affichent un aperçu miniature généré depuis l'image PNG stockée en base64. Au survol, PasteGlide ouvre aussi un aperçu agrandi dans une bulle flottante.

PasteGlide lance aussi un OCR local sur les images avec Vision.framework d'Apple. Aucun binaire Tesseract, installation Homebrew ou dépendance externe n'est nécessaire. Le texte reconnu apparaît dans la bulle de prévisualisation et peut être retrouvé via la recherche.

Au démarrage, PasteGlide complète automatiquement l'OCR des anciennes images qui étaient déjà présentes dans la base avant l'ajout de cette fonctionnalité.

Les mots de passe sont détectés par heuristique: texte court sans espace, avec une combinaison de lettres, chiffres ou symboles. Cette détection n'est pas parfaite, car macOS ne fournit pas le contexte d'origine du contenu copié.

## Stockage SQLite

La base de données est créée automatiquement ici:

```text
~/Library/Application Support/PasteGlide/history.sqlite
```

Elle contient par défaut les 100 derniers éléments copiés. Cette limite, la rétention en jours, l'OCR, la touche du raccourci, la largeur du panneau et les applications exclues se configurent dans le menu `PasteGlide > Préférences`.

Schéma logique:

- `id`: identifiant SQLite
- `kind`: type de carte
- `content`: contenu complet
- `preview`: aperçu affiché dans la carte
- `ocr_text`: texte reconnu dans les images via OCR
- `ocr_attempted`: indique qu'une image a déjà été traitée par OCR, même si aucun texte n'a été reconnu
- `is_pinned`: indique qu'une carte est épinglée
- `created_at`: date de création
- `content_hash`: hash utilisé pour éviter les doublons consécutifs

Les images sont converties en PNG puis stockées en base64 dans `content`. Le texte reconnu dans ces images est stocké séparément dans `ocr_text`.

## Interface

Le panneau d'historique est un `NSPanel` flottant:

- positionné au-dessus du Dock
- centré sur l'écran principal
- affiché sur tous les espaces macOS
- équipé d'un champ de recherche en haut
- composé d'un défilement horizontal de cartes

Chaque carte possède un contour coloré selon son type, une zone de contenu plus large, et un badge ou une miniature à gauche. Les cartes texte affichent un compteur de caractères dans le badge et un aperçu complet au survol; les cartes image affichent une miniature et un aperçu agrandi au survol.

Le menu de barre système permet aussi d'exporter ou d'importer une base SQLite d'historique.

## Architecture

Le code est séparé en trois cibles SwiftPM:

- `PasteGlideCore`: logique applicative, SQLite, OCR, UI AppKit et préférences
- `PasteGlide`: lanceur macOS minimal qui démarre `AppDelegate`
- `PasteGlideCoreTests`: tests exécutables sans dépendance à XCTest, adaptés à la toolchain locale

## Commandes utiles

Compiler:

```bash
swift build
```

Lancer les tests cœur:

```bash
swift run PasteGlideCoreTests
```

Créer une application macOS datée dans `dist/`:

```bash
./scripts/build_app.sh
```

Le bundle généré suit ce format:

```text
dist/PasteGlide_YYYY-MM-DD_HH-MM.app
```

Lancer:

```bash
swift run
```

Vérifier l'état Git:

```bash
git status --short
```

## Dépannage

Si le raccourci `⌥⌘V` ne répond pas, vérifie qu'aucune autre application n'utilise déjà cette combinaison.

Si l'historique semble vide, copie un nouvel élément après le lancement de PasteGlide: l'application surveille les changements du presse-papier pendant qu'elle est active.

Si tu veux repartir d'un historique vide, quitte PasteGlide puis supprime la base:

```bash
rm ~/Library/Application\ Support/PasteGlide/history.sqlite
```

La base sera recréée au prochain lancement.
