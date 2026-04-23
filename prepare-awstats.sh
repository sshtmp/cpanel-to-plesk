#!/usr/bin/env bash
set -u
shopt -s nullglob

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date '+%F %T')" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date '+%F %T')" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage:
  ./$SCRIPT_NAME -P destination_domain [-s source_domain] [-o cpanel_name] [-h]

Options:
  -P   Destination domain in Plesk (required)
  -s   Source domain where tmp/awstats is located (optional)
       If not specified, it is assumed to be the same as -P
  -o   Old domain name in cPanel (optional, for addon domains)
  -h   Help

Examples:
  # Main domain (source = destination)
  ./$SCRIPT_NAME -P example.com
  
  # Addon domain: files are in the main domain's tmp
  ./$SCRIPT_NAME -P addon.info -s example.com
  
  # With manual cPanel name mapping
  ./$SCRIPT_NAME -P addon2.info -s example.com -o addon2.example.com
EOF
}

ascii_header() {
  cat <<'EOF'
┏━╸┏━┓┏━┓┏┓╻┏━╸╻     ╺┳╸┏━┓   ┏━┓╻  ┏━╸┏━┓╻┏
┃  ┣━┛┣━┫┃┗┫┣╸ ┃      ┃ ┃ ┃   ┣━┛┃  ┣╸ ┗━┓┣┻┓
┗━╸╹  ╹ ╹╹ ╹┗━╸┗━╸    ╹ ┗━┛   ╹  ┗━╸┗━╸┗━┛╹ ╹

     Script to migrate AWStats statistics
            from cPanel to Plesk.
 Forked from plesk/kb-scripts, Edited by sshtmp
EOF
}

confirm() {
  local prompt="$1"
  local reply
  read -r -p "$prompt [y/N]: " reply
  case "${reply,,}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

declare -A CPANEL_TO_PLESK=(
  ["borradodatos.borradodatos.com"]="borradodatos.com"
  ["borradocintas.borradodatos.com"]="borradocintas.info"
  ["borradodatosseguro.borradodatos.com"]="borradodatosseguro.info"
)

get_cpanel_name() {
  local plesk_domain="$1"
  
  for cpanel_name in "${!CPANEL_TO_PLESK[@]}"; do
    if [[ "${CPANEL_TO_PLESK[$cpanel_name]}" == "$plesk_domain" ]]; then
      echo "$cpanel_name"
      return 0
    fi
  done
  
  echo "$plesk_domain"
  return 0
}

find_site_root() {
  local domain="$1"
  local candidate
  local candidates=(
    "/var/www/vhosts/$domain"
    "/var/www/vhosts/$domain/httpdocs"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate" ]]; then
      if [[ -d "$candidate/httpdocs" && -d "$candidate/tmp" ]] || [[ -d "$candidate/../httpdocs" && -d "$candidate/tmp" ]]; then
        if [[ -d "$candidate/httpdocs" && -d "$candidate/tmp" ]]; then
          printf '%s\n' "$candidate"
          return 0
        fi
      fi
    fi
  done

  while IFS= read -r candidate; do
    if [[ -d "$candidate/httpdocs" && -d "$candidate/tmp" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(find /var/www/vhosts -maxdepth 3 -type d -name "$domain" 2>/dev/null | sort)

  return 1
}

rename_and_move_txts() {
  local source_dir="$1"
  local target_dir="$2"
  local suffix="$3"
  local kind="$4"
  local cpanel_name="$5"
  local files=()

  if [[ ! -d "$source_dir" ]]; then
    log "Source directory for $kind does not exist: $source_dir"
    return 0
  fi

  mkdir -p "$target_dir"

  files=("$source_dir"/awstats*."$cpanel_name".txt)
  if (( ${#files[@]} == 0 )); then
    log "No .txt files found for cPanel name '$cpanel_name' in $source_dir ($kind)."
    return 0
  fi

  log "Processing ${#files[@]} $kind file(s) from: $source_dir"
  log "Filtering by cPanel name: $cpanel_name"
  log "Destination: $target_dir"

  local file base newname dest
  for file in "${files[@]}"; do
    base="$(basename "$file")"
    newname="${base%.txt}${suffix}.txt"
    dest="$target_dir/$newname"

    log "Renaming: $base -> $newname"
    log "Moving to: $dest"
    mv -f -- "$file" "$dest"
  done
}

DOMAIN_DEST=""
DOMAIN_SOURCE=""
CPANEL_NAME=""

while getopts ":P:s:o:h" opt; do
  case "$opt" in
    P) DOMAIN_DEST="$OPTARG" ;;
    s) DOMAIN_SOURCE="$OPTARG" ;;
    o) CPANEL_NAME="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    :)
      die "Missing argument for -$OPTARG"
      ;;
    \?)
      die "Invalid option: -$OPTARG"
      ;;
  esac
done

[[ -n "$DOMAIN_DEST" ]] || { usage; die "You must specify the destination domain with -P domain.com"; }

if [[ -z "$DOMAIN_SOURCE" ]]; then
  DOMAIN_SOURCE="$DOMAIN_DEST"
  log "No source domain specified (-s), using the same as destination: $DOMAIN_SOURCE"
fi

if [[ -z "$CPANEL_NAME" ]]; then
  CPANEL_NAME="$(get_cpanel_name "$DOMAIN_DEST")"
  log "Inferred cPanel name: $CPANEL_NAME"
fi

ascii_header
echo
log "Destination domain (Plesk): $DOMAIN_DEST"
log "Source domain (cPanel tmp): $DOMAIN_SOURCE"
log "Name in cPanel files: $CPANEL_NAME"

log "Looking for the root path of the source domain $DOMAIN_SOURCE..."
SITE_ROOT_SOURCE="$(find_site_root "$DOMAIN_SOURCE")" || die "Could not locate the root path of $DOMAIN_SOURCE in /var/www/vhosts"

PLESK_STATS_DIR="/var/www/vhosts/system/$DOMAIN_DEST/statistics/webstat"
PLESK_STATS_SSL_DIR="/var/www/vhosts/system/$DOMAIN_DEST/statistics/webstat-ssl"

TMP_DIR="$SITE_ROOT_SOURCE/tmp"
CPANEL_AWSTATS_DIR="$TMP_DIR/awstats"
CPANEL_AWSTATS_SSL_DIR="$CPANEL_AWSTATS_DIR/ssl"

echo
log "Calculated paths:"
printf '  Source root (source domain):  %s\n' "$SITE_ROOT_SOURCE"
printf '  Source tmp:                   %s\n' "$TMP_DIR"
printf '  cPanel awstats (HTTP):        %s\n' "$CPANEL_AWSTATS_DIR"
printf '  awstats SSL (HTTPS):          %s\n' "$CPANEL_AWSTATS_SSL_DIR"
printf '  Destination HTTP (Plesk):     %s\n' "$PLESK_STATS_DIR"
printf '  Destination HTTPS (Plesk):    %s\n' "$PLESK_STATS_SSL_DIR"
echo

if ! confirm "Are these paths correct and does everything exist where it should?"; then
  die "Cancelled by user"
fi

log "Confirmed. Proceeding with the process."

log "Preparing HTTP statistics..."
rename_and_move_txts "$CPANEL_AWSTATS_DIR" "$PLESK_STATS_DIR" "-http" "HTTP" "$CPANEL_NAME"

log "Preparing HTTPS statistics..."
rename_and_move_txts "$CPANEL_AWSTATS_SSL_DIR" "$PLESK_STATS_SSL_DIR" "-https" "HTTPS" "$CPANEL_NAME"

echo
log "Preparation process completed."

if confirm "Do you want to run ./rebuild-awstats.sh -R $DOMAIN_DEST to rebuild the statistics?"; then
  REBUILD_SCRIPT="$SCRIPT_DIR/rebuild-awstats.sh"
  if [[ ! -f "$REBUILD_SCRIPT" ]]; then
    die "Cannot find $REBUILD_SCRIPT"
  fi

  log "Running rebuild-awstats.sh for $DOMAIN_DEST..."
  bash "$REBUILD_SCRIPT" -R "$DOMAIN_DEST"
  log "Rebuild completed."
else
  log "Rebuild was not executed. All done; if you want to rebuild, you'll have to do it manually."
fi

exit 0
