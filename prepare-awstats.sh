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
  ./$SCRIPT_NAME destination_domain [-s source_domain] [-h]

Arguments:
  destination_domain    Domain in Plesk (required)
  -s source_domain      Source domain where to search tmp files (optional)
  -h                    Show this help

Examples:
  ./$SCRIPT_NAME midominio.com
  ./$SCRIPT_NAME midominio.com -s origencpanel.com

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

detect_real_domain() {
  local cpanel_name="$1"
  local domain_prefix="${cpanel_name%%.*}"
  
  log "Searching for real domain for prefix: $domain_prefix"
  
  local found_domain=""
  while IFS= read -r domain_dir; do
    local domain_name="$(basename "$domain_dir")"
    if [[ "$domain_name" == "$domain_prefix".* ]] || [[ "$domain_name" == "$domain_prefix" ]]; then
      found_domain="$domain_name"
      log "Found: $found_domain"
      break
    fi
  done < <(find /var/www/vhosts/system -maxdepth 1 -type d 2>/dev/null | grep -v "/system$" | sort)
  
  if [[ -n "$found_domain" ]]; then
    echo "$found_domain"
    return 0
  else
    warn "Could not detect real domain for '$cpanel_name', using as is"
    echo "$cpanel_name"
    return 0
  fi
}

rename_and_move_txts() {
  local source_dir="$1"
  local target_dir="$2"
  local suffix="$3"
  local kind="$4"
  local search_pattern="$5"
  local files=()

  if [[ ! -d "$source_dir" ]]; then
    warn "Source directory for $kind does not exist: $source_dir"
    return 0
  fi

  mkdir -p "$target_dir"

  local all_files=("$source_dir"/awstats*.txt)
  if (( ${#all_files[@]} == 0 )); then
    log "No .txt files found in $source_dir ($kind)."
    return 0
  fi

  local file base domain_part
  for file in "${all_files[@]}"; do
    base="$(basename "$file")"
    domain_part="${base#awstats[0-9][0-9][0-9][0-9][0-9][0-9].}"
    domain_part="${domain_part%.txt}"
    if [[ "$domain_part" == "$search_pattern" ]]; then
      files+=("$file")
    fi
  done

  if (( ${#files[@]} == 0 )); then
    log "No files with exact domain pattern '$search_pattern' in $source_dir ($kind)."
    return 0
  fi

  log "Processing ${#files[@]} file(s) of $kind from: $source_dir"
  log "Filtering exact pattern: $search_pattern"
  log "Destination: $target_dir"

  local newname dest
  for file in "${files[@]}"; do
    base="$(basename "$file")"
    newname="${base%.txt}${suffix}.txt"
    dest="$target_dir/$newname"

    log "Renaming: $base -> $newname"
    log "Moving to: $dest"
    mv -f -- "$file" "$dest"
  done
}

# ---------- ARGUMENT PARSING ----------
# First positional argument is destination domain
DOMAIN_DEST=""
DOMAIN_SOURCE=""

# Manual parsing because we have a positional arg
if [[ $# -eq 0 ]]; then
  usage
  die "Destination domain is required"
fi

# The first argument (if not starting with -) is DOMAIN_DEST
if [[ "$1" != "-"* ]]; then
  DOMAIN_DEST="$1"
  shift
fi

# Parse remaining options
while getopts ":s:h" opt; do
  case "$opt" in
    s) DOMAIN_SOURCE="$OPTARG" ;;
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

if [[ -z "$DOMAIN_DEST" ]]; then
  usage
  die "You must specify the destination domain as first argument"
fi

if [[ -z "$DOMAIN_SOURCE" ]]; then
  DOMAIN_SOURCE="$DOMAIN_DEST"
  log "Option -s not specified, using the same domain as source: $DOMAIN_SOURCE"
fi

# ---------- MAIN ----------
ascii_header
echo

log "Destination domain (Plesk): $DOMAIN_DEST"
log "Source domain (tmp):        $DOMAIN_SOURCE"

log "Searching for source domain root path: $DOMAIN_SOURCE"
SITE_ROOT_SOURCE="$(find_site_root "$DOMAIN_SOURCE")" || die "Could not locate the root path for $DOMAIN_SOURCE"

log "Verifying destination domain root path: $DOMAIN_DEST"
SITE_ROOT_DEST="$(find_site_root "$DOMAIN_DEST")" || die "Could not locate the root path for $DOMAIN_DEST"

TMP_DIR="$SITE_ROOT_SOURCE/tmp"
CPANEL_AWSTATS_DIR="$TMP_DIR/awstats"
CPANEL_AWSTATS_SSL_DIR="$CPANEL_AWSTATS_DIR/ssl"

PLESK_STATS_DIR="/var/www/vhosts/system/$DOMAIN_DEST/statistics/webstat"
PLESK_STATS_SSL_DIR="/var/www/vhosts/system/$DOMAIN_DEST/statistics/webstat-ssl"

echo
log "Calculated paths:"
printf '  Source (tmp):          %s\n' "$SITE_ROOT_SOURCE"
printf '  Destination (root):    %s\n' "$SITE_ROOT_DEST"
printf '  awstats cPanel:        %s\n' "$CPANEL_AWSTATS_DIR"
printf '  awstats SSL:           %s\n' "$CPANEL_AWSTATS_SSL_DIR"
printf '  Destination HTTP:      %s\n' "$PLESK_STATS_DIR"
printf '  Destination HTTPS:     %s\n' "$PLESK_STATS_SSL_DIR"
echo

if ! confirm "Are these paths correct?"; then
  die "Cancelled by user"
fi

# ---------- SMART PATTERN DETECTION ----------
log "Analyzing available files to determine the correct pattern..."

SEARCH_PATTERN="$DOMAIN_DEST"

if [[ -d "$CPANEL_AWSTATS_DIR" ]]; then
  shopt -s nullglob
  all_files=("$CPANEL_AWSTATS_DIR"/awstats*.txt)
  shopt -u nullglob
  
  if (( ${#all_files[@]} > 0 )); then
    log "Found ${#all_files[@]} total files, scanning for pattern matching destination domain..."
    
    FOUND_MATCH=0
    for file in "${all_files[@]}"; do
      base="$(basename "$file")"
      pattern="${base#awstats[0-9][0-9][0-9][0-9][0-9][0-9].}"
      pattern="${pattern%.txt}"
      
      # Get real domain for this pattern
      real_domain="$(detect_real_domain "$pattern")"
      
      if [[ "$real_domain" == "$DOMAIN_DEST" ]]; then
        log "Found matching pattern: $pattern (real domain: $real_domain)"
        SEARCH_PATTERN="$pattern"
        FOUND_MATCH=1
        break
      fi
    done
    
    if [[ $FOUND_MATCH -eq 0 ]]; then
      warn "Could not find any pattern matching destination domain '$DOMAIN_DEST'"
      warn "Will use destination domain as pattern: $SEARCH_PATTERN"
      warn "This may not find any files to move"
    fi
  else
    log "No awstats files found in $CPANEL_AWSTATS_DIR"
  fi
else
  log "Directory $CPANEL_AWSTATS_DIR does not exist"
fi

log "Final search pattern: $SEARCH_PATTERN"
echo

if ! confirm "Use this pattern to filter files?"; then
  log "You can run again with different arguments"
  die "Cancelled by user"
fi

# ---------- MIGRATION ----------
log "Preparing HTTP statistics..."
rename_and_move_txts "$CPANEL_AWSTATS_DIR" "$PLESK_STATS_DIR" "-http" "HTTP" "$SEARCH_PATTERN"

log "Preparing HTTPS statistics..."
rename_and_move_txts "$CPANEL_AWSTATS_SSL_DIR" "$PLESK_STATS_SSL_DIR" "-https" "HTTPS" "$SEARCH_PATTERN"

echo
log "Preparation process completed."

if confirm "Do you want to run ./rebuild-awstats.sh -R $DOMAIN_DEST to rebuild statistics?"; then
  REBUILD_SCRIPT="$SCRIPT_DIR/rebuild-awstats.sh"
  if [[ ! -f "$REBUILD_SCRIPT" ]]; then
    die "Cannot find $REBUILD_SCRIPT"
  fi

  log "Running rebuild-awstats.sh for $DOMAIN_DEST..."
  bash "$REBUILD_SCRIPT" -R "$DOMAIN_DEST"
  log "Rebuild completed."
else
  log "Rebuild has not been executed."
fi

exit 0