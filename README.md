# PasteGlide

PasteGlide est un gestionnaire de presse-papier macOS natif écrit en Swift/AppKit. Il conserve un historique local SQLite, classe les contenus copiés, affiche des cartes rapides et peut se placer en bas, en haut, sur les côtés ou au milieu de l'écran.

English documentation: [README.en.md](README.en.md)

## Prérequis

- macOS 14 ou plus récent
- Swift 6 ou plus récent
- Xcode Command Line Tools
- SQLite système via `libsqlite3`
- Vision.framework pour l'OCR local des images

## Lancement

Depuis le dossier du projet:

```bash
swift run
```

Créer une app macOS dans `dist/`:

```bash
./scripts/build_app.sh
```

Le bundle généré suit ce format:

```text
dist/PasteGlide_YYYY-MM-DD_HH-MM.app
```

## Raccourcis

Le raccourci global par défaut est `⌥⌘V`. Il affiche ou masque le panneau d'historique.

Dans le panneau:

- `←` / `→` / `↑` / `↓`: sélectionner une carte
- `Entrée`: copier la carte sélectionnée
- `Espace`: afficher la prévisualisation
- `Suppr`: supprimer la carte sélectionnée
- `⌘F`: placer le curseur dans la recherche
- `⌘1` à `⌘7`: changer de filtre
- `Échap`: fermer le panneau

## Utilisation

1. Lance PasteGlide.
2. Copie du texte, une URL, un lien YouTube, une suite de chiffres, un mot de passe probable ou une image.
3. Appuie sur `⌥⌘V`.
4. Recherche, filtre ou navigue au clavier.
5. Clique sur une carte ou appuie sur `Entrée` pour remettre son contenu dans le presse-papier.

Un clic droit sur une carte donne accès aux actions rapides:

- copier en texte brut;
- ouvrir un lien;
- enregistrer une image;
- révéler ou masquer un mot de passe;
- épingler ou désépingler;
- supprimer la carte;
- supprimer toutes les cartes du même type.

## Filtres et statistiques

Sous la recherche, PasteGlide affiche:

- le nombre total d'objets mémorisés;
- le nombre d'images, textes, chiffres, mots de passe et liens YouTube;
- la date et l'heure de la dernière carte.

Les filtres rapides permettent d'afficher:

- tous les éléments;
- uniquement les éléments épinglés;
- YouTube;
- texte;
- mots de passe;
- chiffres;
- images.

## Positions du panneau

Dans les préférences, le panneau peut être affiché:

- en bas, au-dessus du Dock;
- en haut;
- à gauche;
- à droite;
- au milieu de l'écran.

Les positions `Gauche`, `Droite` et `Milieu` utilisent une colonne avec défilement vertical. Les positions `Bas` et `Haut` utilisent une rangée avec défilement horizontal.

## Confidentialité

PasteGlide peut:

- ne pas mémoriser les mots de passe probables;
- masquer les contenus sensibles dans les cartes;
- exclure des applications par nom ou bundle id;
- mettre la capture en pause pendant 5, 15 ou 30 minutes depuis le menu de barre macOS.

La détection des mots de passe est heuristique: macOS ne fournit pas le contexte d'origine du contenu copié.

## Images et OCR

Les images sont converties en PNG, stockées en base64 dans SQLite, puis affichées sous forme de miniature.

Si l'OCR est activé, PasteGlide utilise Vision.framework localement. Le texte reconnu est indexé par la recherche et affiché dans la prévisualisation.

## Nettoyage

Les préférences permettent de:

- définir le nombre d'éléments à conserver;
- définir une rétention en jours;
- supprimer les images;
- supprimer les éléments plus vieux que la rétention configurée;
- vider tout l'historique.

Les éléments épinglés sont conservés par la rétention automatique.

## Stockage

La base locale est créée ici:

```text
~/Library/Application Support/PasteGlide/history.sqlite
```

Schéma logique:

- `id`: identifiant SQLite
- `kind`: type de carte
- `content`: contenu complet
- `preview`: aperçu affiché
- `ocr_text`: texte reconnu dans les images
- `ocr_attempted`: statut de traitement OCR
- `is_pinned`: carte épinglée
- `created_at`: date de création
- `content_hash`: hash anti-doublon consécutif

## Import et export

Le menu de barre macOS permet:

- d'exporter l'historique SQLite;
- d'importer un historique existant.

## Tests

```bash
swift run PasteGlideCoreTests
```

## Dépannage

Si `⌥⌘V` ne répond pas, vérifie qu'aucune autre app n'utilise déjà ce raccourci.

Si l'historique semble vide, copie un nouvel élément après le lancement: PasteGlide surveille le presse-papier uniquement pendant qu'il est actif.

Pour repartir d'un historique vide:

```bash
rm ~/Library/Application\ Support/PasteGlide/history.sqlite
```
