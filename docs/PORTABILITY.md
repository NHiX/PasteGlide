# PasteGlide Portability / Portabilite

## FR

PasteGlide est aujourd'hui une application macOS native. Le code utilise AppKit, Carbon, Vision.framework, `NSPasteboard`, `NSStatusBar`, `NSPanel` et les conventions d'installation macOS. Ces API n'existent pas sur Linux ou Windows, donc un paquet `.deb`, `.rpm`, `.msi` ou `.zip` ne peut pas etre produit correctement tant qu'un port natif n'existe pas.

Le travail ajoute ici prepare le packaging sans masquer cette contrainte:

- `PasteGlideShared` contient maintenant les modeles, la classification, la recherche/filtrage, les positions de panneau et les regles de preferences sans AppKit, ce qui donne une premiere base compilable pour les ports.
- `PasteGlidePortable` est un premier executable portable de validation qui depend uniquement de `PasteGlideShared`.
- `scripts/build_linux_packages.sh` package un binaire Linux existant en `.deb` et `.rpm` via `nfpm`.
- `scripts/build_windows_packages.ps1` package un dossier Windows existant en `.zip` et, si WiX est installe, en `.msi`.
- `packaging/linux/pasteglide.desktop` fournit l'integration bureau Linux.
- `packaging/windows/PasteGlide.wxs` fournit le manifeste WiX pour l'installeur Windows.

### Plan de portage

1. Continuer l'extraction de la base SQLite et de l'import/export dans `PasteGlideShared`.
2. Remplacer les services macOS par des interfaces de plateforme: presse-papier, raccourci global, OCR, stockage d'images, notifications et ouverture de liens.
3. Implementer une UI Linux avec GTK/libadwaita ou Qt, puis une UI Windows avec WinUI, Qt ou une fine couche native.
4. Produire un binaire Linux `dist/linux/PasteGlide` et un dossier Windows `dist/windows/PasteGlide/PasteGlide.exe`.
5. Lancer les scripts de packaging multiplateforme.

### Validation portable actuelle

Le binaire portable ne remplace pas encore l'app complete, mais il valide le noyau partage sur les plateformes non macOS:

```bash
swift run PasteGlidePortable classify "https://example.com"
swift run PasteGlidePortable search-demo "type:text pinned:true invoice"
swift run PasteGlidePortable settings-demo
```

### Packaging automatique

Le workflow GitHub Actions `Portable Packages` construit ce binaire portable en environnement natif Linux et Windows. Il publie des artefacts de workflow:

- Linux: `.deb` et `.rpm`
- Windows: `.zip` et `.msi`

Quand le workflow est declenche par un tag `v*`, ces quatre paquets sont aussi attaches a la release GitHub `PasteGlide` avec des notes FR/EN, sans date ni heure dans le nom de release.

Ces paquets valident la chaine de compilation/packaging multiplateforme. Ils ne remplacent pas encore l'application graphique complete tant que les UI Linux et Windows ne sont pas implementees.

### Commandes attendues apres portage

Linux:

```bash
./scripts/build_linux_packages.sh dist/linux/PasteGlide
```

Windows PowerShell:

```powershell
./scripts/build_windows_packages.ps1 -AppDir dist/windows/PasteGlide
```

## EN

PasteGlide is currently a native macOS app. The code uses AppKit, Carbon, Vision.framework, `NSPasteboard`, `NSStatusBar`, `NSPanel`, and macOS installation conventions. These APIs do not exist on Linux or Windows, so a useful `.deb`, `.rpm`, `.msi`, or `.zip` cannot be produced until native ports exist.

The work added here prepares packaging without hiding that constraint:

- `PasteGlideShared` now contains the models, classification, search/filtering, panel positions, and preference rules without AppKit, providing a first compilable base for the ports.
- `PasteGlidePortable` is a first portable validation executable that depends only on `PasteGlideShared`.
- `scripts/build_linux_packages.sh` packages an existing Linux binary into `.deb` and `.rpm` with `nfpm`.
- `scripts/build_windows_packages.ps1` packages an existing Windows app folder into `.zip` and, when WiX is installed, `.msi`.
- `packaging/linux/pasteglide.desktop` provides Linux desktop integration.
- `packaging/windows/PasteGlide.wxs` provides the WiX installer manifest for Windows.

### Porting Plan

1. Continue extracting SQLite storage and import/export into `PasteGlideShared`.
2. Replace macOS services with platform interfaces: clipboard, global hotkey, OCR, image storage, notifications, and URL opening.
3. Implement a Linux UI with GTK/libadwaita or Qt, then a Windows UI with WinUI, Qt, or a thin native layer.
4. Produce a Linux binary at `dist/linux/PasteGlide` and a Windows folder at `dist/windows/PasteGlide/PasteGlide.exe`.
5. Run the cross-platform packaging scripts.

### Current Portable Validation

The portable binary does not replace the complete app yet, but it validates the shared core on non-macOS platforms:

```bash
swift run PasteGlidePortable classify "https://example.com"
swift run PasteGlidePortable search-demo "type:text pinned:true invoice"
swift run PasteGlidePortable settings-demo
```

### Automated Packaging

The `Portable Packages` GitHub Actions workflow builds this portable binary in native Linux and Windows environments. It publishes workflow artifacts:

- Linux: `.deb` and `.rpm`
- Windows: `.zip` and `.msi`

When the workflow is triggered by a `v*` tag, these four packages are also attached to the `PasteGlide` GitHub release with FR/EN notes, without a date or time in the release name.

These packages validate the cross-platform build/packaging chain. They do not replace the complete graphical app until the Linux and Windows UIs are implemented.

### Expected Commands After Porting

Linux:

```bash
./scripts/build_linux_packages.sh dist/linux/PasteGlide
```

Windows PowerShell:

```powershell
./scripts/build_windows_packages.ps1 -AppDir dist/windows/PasteGlide
```
