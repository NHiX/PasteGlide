# PasteGlide

PasteGlide est un gestionnaire de presse-papier macOS natif écrit en Swift/AppKit. Il conserve un historique local, classe les contenus copiés, affiche des cartes rapides et peut se placer en bas, en haut, sur les côtés ou au milieu de l'écran.

English documentation: [README.en.md](README.en.md)

## Prérequis

- macOS 14 ou plus récent
- Swift 6 ou plus récent
- Xcode Command Line Tools
- SQLite système via `libsqlite3`
- Vision.framework pour l'OCR local des images

## Lancement

```bash
swift run
```

Créer une app macOS dans `dist/`:

```bash
./scripts/build_app.sh
```

Créer le DMG de distribution avec l'app et un raccourci vers `/Applications`:

```bash
./scripts/build_dmg.sh
```

Créer aussi le zip de `PasteGlide.app` publié avec les releases:

```bash
./scripts/build_zip.sh
```

Les releases GitHub publient `PasteGlide.dmg` et `PasteGlide.app.zip`. Le DMG contient `PasteGlide.app` et un raccourci `Applications` pour installer l'app par glisser-déposer. L'app est signée ad-hoc pour garder un bundle macOS cohérent; sans certificat Apple Developer ID et notarisation, macOS peut encore demander une ouverture via clic droit puis `Ouvrir`.

Pour produire un DMG notarizé par Apple, il faut un compte Apple Developer, un certificat `Developer ID Application` et un profil `notarytool` enregistré dans le trousseau. Ensuite:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Votre Nom (TEAMID)" \
NOTARYTOOL_PROFILE="pasteglide-notary" \
./scripts/notarize_dmg.sh
```

Sans notarisation, si macOS affiche "Apple n'a pas pu confirmer que PasteGlide ne contenait pas de logiciel malveillant", ouvrez `Réglages Système > Confidentialité et sécurité`, puis cliquez sur `Ouvrir quand même`, ou faites clic droit sur l'app puis `Ouvrir`.

## Raccourcis

Le raccourci global par défaut est `⌥⌘V`.

Dans le panneau:

- `←` / `→` / `↑` / `↓`: sélectionner une carte
- `Entrée`: copier et fermer
- `Espace`: afficher la prévisualisation
- `Suppr`: supprimer la carte
- `⌘F`: focus recherche
- `⌘1` à `⌘8`: changer de filtre
- `Échap`: fermer

## Cartes et actions

PasteGlide détecte:

- liens YouTube;
- liens web généraux;
- texte;
- mots de passe probables;
- chiffres;
- images.

Un clic droit sur une carte permet de copier sans fermer, copier en texte brut, ouvrir un lien, enregistrer une image, révéler un mot de passe, épingler, supprimer une carte ou supprimer toutes les cartes du même type.

## Recherche

La recherche texte fonctionne sur le type, l'aperçu, le contenu texte et l'OCR.

Opérateurs disponibles:

- `type:image`, `type:text`, `type:url`, `type:youtube`, `type:password`, `type:number`
- `pinned:true`
- `after:2h`, `after:7d`, `after:2w`

Exemple:

```text
type:image after:7d facture
```

## Filtres et statistiques

Sous la recherche, PasteGlide affiche le total mémorisé, les compteurs par type et la date de dernière carte. Les filtres rapides affichent tous les éléments, les épinglés, YouTube, liens, texte, mots de passe, chiffres ou images.

## Positions du panneau

Le panneau peut être affiché en bas, en haut, à gauche, à droite ou au milieu de l'écran. Les positions gauche, droite et milieu utilisent une colonne avec défilement vertical; haut et bas utilisent une rangée horizontale.

## Confidentialité

PasteGlide peut:

- ne pas mémoriser les mots de passe probables;
- masquer les contenus sensibles;
- ne jamais capturer les images;
- limiter la taille maximale des images capturées;
- exclure des applications;
- mettre la capture en pause pendant 5, 15 ou 30 minutes.

## Empreinte mémoire

Les images originales ne sont plus chargées avec la liste des cartes. PasteGlide:

- stocke les images originales en fichiers dans `Application Support`;
- garde seulement une miniature légère pour les cartes;
- charge l'image originale à la demande pour copier, prévisualiser ou sauvegarder;
- utilise un cache image borné;
- supprime les fichiers image associés lors du nettoyage.

## Images et OCR

Les images capturées sont enregistrées en PNG. Une miniature est conservée pour l'affichage rapide. Si l'OCR est activé, Vision.framework analyse localement les images et rend le texte reconnu recherchable.

## Nettoyage

Les préférences permettent de définir la limite d'historique, la rétention, de supprimer les images, de supprimer les éléments plus vieux que la rétention ou de vider tout l'historique. Les éléments épinglés survivent à la rétention automatique.

## Stockage

La base SQLite est créée ici:

```text
~/Library/Application Support/PasteGlide/history.sqlite
```

Les images externalisées sont stockées ici:

```text
~/Library/Application Support/PasteGlide/Images/
```

## Import et export

Le menu de barre macOS permet d'importer/exporter l'historique SQLite et JSON.

## Tests

```bash
swift run PasteGlideCoreTests
```

## Dépannage

Si `⌥⌘V` ne répond pas, vérifie qu'aucune autre app n'utilise déjà ce raccourci.

Pour repartir d'un historique vide:

```bash
rm ~/Library/Application\ Support/PasteGlide/history.sqlite
rm -rf ~/Library/Application\ Support/PasteGlide/Images
```
