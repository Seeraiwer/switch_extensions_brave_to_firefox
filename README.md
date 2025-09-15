# Brave → Firefox : Correspondance d’extensions

Un script **Bash** qui scanne les extensions installées dans Brave, lit leurs `manifest.json`, et propose les équivalents disponibles sur [addons.mozilla.org (AMO)](https://addons.mozilla.org).

## ✨ Fonctionnalités
- Scanne automatiquement les extensions installées dans : `~/.config/BraveSoftware/Brave-Browser/Default/Extensions/`
- Récupère **nom, version, description** à partir du `manifest.json`.
- Résout correctement les noms de type `__MSG_*__` via les fichiers `_locales`.
- Interroge l’API publique d’AMO pour trouver les équivalents Firefox.
- Affiche un tableau clair dans le terminal.
- Exporte en **CSV** ou **JSON**.
- Filtre : ne suggère que les extensions portant le **même nom**.

## 📦 Prérequis
- **bash**
- [jq](https://stedolan.github.io/jq/)
- [curl](https://curl.se/)

### Installation rapide
```bash
# Debian/Ubuntu
sudo apt-get install jq curl

# macOS (brew)
brew install jq curl
````

## 🚀 Utilisation

```bash
# Scan simple avec 5 suggestions max par extension
bash brave_to_firefox_extensions.sh --limit 5

# Export CSV et JSON
bash brave_to_firefox_extensions.sh --csv brave_to_firefox.csv --json brave_to_firefox.json

# Mode hors-ligne (juste l’inventaire Brave, sans requêtes réseau)
bash brave_to_firefox_extensions.sh --no-network

# Mode verbeux (debug des chemins et parsing)
bash brave_to_firefox_extensions.sh --verbose
```

## 📂 Exemple de sortie

```text
➡  GHunt Companion  (id: dpdcofblfbmmnikcbmmiakkclocadjab, v2.0.0)
    Web Store: https://chrome.google.com/webstore/detail/dpdcofblfbmmnikcbmmiakkclocadjab
    1. GHunt Companion — note 5.0 — 1448 utilisateurs
       https://addons.mozilla.org/fr/firefox/addon/ghunt-companion/
```

## 🔧 Options disponibles

| Option           | Description                                  |
| ---------------- | -------------------------------------------- |
| `--limit N`      | Limite le nombre de suggestions (défaut : 5) |
| `--csv FICHIER`  | Exporte les résultats en CSV                 |
| `--json FICHIER` | Exporte les résultats en JSON                |
| `--no-network`   | Désactive les requêtes AMO (inventaire seul) |
| `--verbose`      | Affiche des infos de debug                   |

## ⚠️ Limitations

* Actuellement le script ne gère que le profil `Default`.
  Pour d’autres profils, adapter la variable `BASE_DIR` dans le script.
* Les correspondances sont basées sur la **recherche de nom** sur AMO : si l’extension n’existe pas côté Firefox, aucune suggestion.

## 📄 Licence
MIT
