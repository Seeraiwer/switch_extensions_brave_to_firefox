#!/usr/bin/env bash
# brave_to_firefox_extensions.sh
#
# Scanne les extensions Brave depuis:
#   /home/$USER/.config/BraveSoftware/Brave-Browser/Default/Extensions/
# et propose des équivalents Firefox (AMO).
#
# Dépendances: jq, curl
# Usage:
#   bash brave_to_firefox_extensions.sh [--limit 5] [--csv out.csv] [--json out.json] [--no-network] [--verbose]
#
set -euo pipefail

# ----------- Options ----------
LIMIT=5
CSV_OUT=""
JSON_OUT=""
NO_NET=0
VERBOSE=0

BASE_DIR="/home/$USER/.config/BraveSoftware/Brave-Browser/Default/Extensions"

# ----------- Helpers ----------
bold() { printf "\033[1m%s\033[0m\n" "$*"; }
err()  { printf "[!] %s\n" "$*" 1>&2; }
die()  { err "$*"; exit 1; }
dbg()  { [[ "$VERBOSE" -eq 1 ]] && printf "[debug] %s\n" "$*" 1>&2 || true; }
need() { command -v "$1" >/dev/null 2>&1 || die "Dépendance manquante: $1"; }

# format flottant robuste (indépendant de la locale)
fmt_float() {
  # usage: fmt_float 4.0911 -> 4.1
  LC_ALL=C printf '%.1f' "$1"
}

need jq
need curl

# ----------- Args ------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)   LIMIT="${2:-5}"; shift 2;;
    --csv)     CSV_OUT="${2:-}"; shift 2;;
    --json)    JSON_OUT="${2:-}"; shift 2;;
    --no-network) NO_NET=1; shift;;
    --verbose) VERBOSE=1; shift;;
    -h|--help)
      sed -n '1,120p' "$0"; exit 0;;
    *) die "Arg inconnu: $1";;
  esac
done

[[ -d "$BASE_DIR" ]] || die "Dossier Extensions introuvable: $BASE_DIR"
bold "Dossier Extensions Brave: $BASE_DIR"

# Ordre de langues pour __MSG_*__ (peut être précédé par default_locale du manifest)
LANGS=("fr" "fr-FR" "en-US")

# Résout __MSG_key__ via _locales/<lang>/messages.json
resolve_name_from_locales() {
  local dir="$1"; shift
  local key_raw="$1"
  local ldir="$dir/_locales"
  [[ -d "$ldir" ]] || return 1

  # essayer clé EXACTE puis lowercase
  local try_keys=("$key_raw" "${key_raw,,}")
  local msgfile val
  for l in "${LANGS[@]}"; do
    msgfile="$ldir/$l/messages.json"
    if [[ -f "$msgfile" ]]; then
      for k in "${try_keys[@]}"; do
        val=$(jq -r --arg k "$k" '.[$k].message // empty' "$msgfile" 2>/dev/null || true)
        if [[ -n "$val" && "$val" != "null" ]]; then
          printf '%s' "$val"; return 0
        fi
      done
    fi
  done
  return 1
}

# Nettoyage simple des requêtes pour AMO
clean_query() {
  sed -E 's/(for|&|\+|\-|™|®)/ /gi; s/[[:space:]]+/ /g; s/^ +| +$//g'
}

# Collections pour exports
CSV_ROWS=()
JSON_ITEMS=()

count=0

# Boucle sur chaque extension (dossier = id)
while IFS= read -r -d '' ext; do
  [[ -d "$ext" ]] || continue
  id="$(basename "$ext")"

  # Trouver la version la plus récente (dossiers enfants)
  latest_dir=""
  if compgen -G "$ext/*/" > /dev/null; then
    latest_dir="$(ls -1d "$ext"/*/ 2>/dev/null | sort -V | tail -n1)"
  fi
  [[ -n "$latest_dir" ]] || { dbg "Aucune version dans $ext"; continue; }

  manifest="$latest_dir/manifest.json"
  [[ -f "$manifest" ]] || { dbg "manifest.json manquant dans $latest_dir"; continue; }

  # Lire manifest
  name="$(jq -r '.name // empty' "$manifest")"
  version="$(jq -r '.version // "?"' "$manifest")"
  desc="$(jq -r '.description // ""' "$manifest")"
  homepage="$(jq -r '.homepage_url // ""' "$manifest")"
  default_locale="$(jq -r '.default_locale // empty' "$manifest")"

  # Ajuster la priorité des langues si default_locale existe
  if [[ -n "$default_locale" && "$default_locale" != "null" ]]; then
    LANGS=("$default_locale" "${default_locale%%-*}" "fr" "fr-FR" "en-US")
  else
    LANGS=("fr" "fr-FR" "en-US")
  fi

  # Résoudre __MSG_*__ si nécessaire
  if [[ "$name" =~ ^__MSG_.*__$ ]]; then
    key="${name#__MSG_}"; key="${key%__}"
    if locname="$(resolve_name_from_locales "$latest_dir" "$key")"; then
      name="$locname"
    fi
  fi
  [[ -z "$name" || "$name" == "null" ]] && name="$id"

  weburl="https://chrome.google.com/webstore/detail/$id"

  bold "➡  $name  (id: $id, v$version)"
  echo "    Web Store: $weburl"

  # ------- Recherche sur AMO -------
  suggestions_json="[]"
  if [[ "$NO_NET" -eq 0 ]]; then
    q="$name"
    suggestions_json=$(curl -sS --get "https://addons.mozilla.org/api/v5/addons/search/" \
       --data-urlencode "q=$q" \
       --data-urlencode "page_size=$LIMIT" \
       --data-urlencode "app=firefox" \
       --data-urlencode "type=extension" \
       --data-urlencode "sort=relevance" \
       --data-urlencode "lang=fr" \
      | jq -c '.results // []' 2>/dev/null || echo '[]')

    # Fallback si rien trouvé: nettoyer la requête
    if [[ "$(jq 'length' <<<"$suggestions_json")" -eq 0 ]]; then
      q2="$(printf '%s' "$q" | clean_query)"
      if [[ -n "$q2" && "$q2" != "$q" ]]; then
        suggestions_json=$(curl -sS --get "https://addons.mozilla.org/api/v5/addons/search/" \
           --data-urlencode "q=$q2" \
           --data-urlencode "page_size=$LIMIT" \
           --data-urlencode "app=firefox" \
           --data-urlencode "type=extension" \
           --data-urlencode "sort=relevance" \
           --data-urlencode "lang=fr" \
          | jq -c '.results // []' 2>/dev/null || echo '[]')
      fi
    fi
  fi

  # Affichage des suggestions (jq en UNE SEULE LIGNE)
i=1
while IFS=$'\t' read -r s_name s_url s_summary s_rating s_users s_rec; do
  [[ -z "$s_name" && -z "$s_url" ]] && continue

  # ne garder que les candidats dont le nom correspond exactement à celui de Brave
  if [[ "${s_name,,}" != "${name,,}" ]]; then
    continue
  fi

  badge=""; [[ "$s_rec" == "true" ]] && badge=" ⭐ Recommandé"
  rtxt=""; [[ "$s_rating" != "" && "$s_rating" != "null" ]] && rtxt=" — note $(fmt_float "$s_rating")"
  utxt=""; [[ "$s_users"  != "" && "$s_users"  != "null" ]] && utxt=" — ${s_users} utilisateurs"

  printf "    %d. %s%s%s%s\n       %s\n" "$i" "$s_name" "$badge" "$rtxt" "$utxt" "$s_url"

  CSV_ROWS+=("$name,$id,$version,$weburl,${s_name} (${s_url})")
  JSON_ITEMS+=("{\"brave\":{\"id\":\"$id\",\"name\":\"$name\",\"version\":\"$version\",\"web\":\"$weburl\"},\"firefox\":{\"name\":\"$s_name\",\"url\":\"$s_url\",\"rating\":$s_rating,\"users\":$s_users,\"recommended\":$s_rec}}")

  i=$((i+1))
done < <(echo "$suggestions_json" | jq -r '.[] | [ (.name.fr // .name["en-US"] // ""), (.url // ""), (.summary.fr // .summary["en-US"] // ""), ((.ratings.average // null)), (.average_daily_users // null), (.is_recommended // false) ] | @tsv')

  count=$((count+1))
  sleep 0.2
done < <(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

bold "Extensions détectées: $count"

# ----------- Exports ----------
if [[ -n "$CSV_OUT" ]]; then
  {
    echo "Brave Name,Brave ID,Version,WebStore URL,Firefox Suggestion"
    for row in "${CSV_ROWS[@]:-}"; do
      IFS=',' read -r bname bid bver burl fsugg <<<"$row"
      printf '"%s","%s","%s","%s","%s"\n' "$bname" "$bid" "$bver" "$burl" "$fsugg"
    done
  } >"$CSV_OUT"
  echo "CSV écrit: $CSV_OUT"
fi

if [[ -n "$JSON_OUT" ]]; then
  printf '[%s]\n' "$(IFS=,; echo "${JSON_ITEMS[*]:-}")" | jq . >"$JSON_OUT"
  echo "JSON écrit: $JSON_OUT"
fi
