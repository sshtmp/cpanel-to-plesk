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
  ./$SCRIPT_NAME destination_domain [-s source_domain] [-p search_pattern] [-f] [-h]

Arguments:
  destination_domain    Domain in Plesk (required)
  -s source_domain      Source domain where to search tmp files (optional)
  -p search_pattern     Manually override the search pattern (e.g., old domain name in files)
  -f, --fix             Clean up already existing files in webstat/ and webstat-ssl/ (rename to standard format)
  -h                    Show this help

Examples:
  ./$SCRIPT_NAME midominio.com
  ./$SCRIPT_NAME midominio.com -s origencpanel.com
  ./$SCRIPT_NAME nuevodominio.net -s cuentaprincipal.com -p viejodominio.com
  ./$SCRIPT_NAME midominio.com -f

EOF
}

ascii_header() {
  cat <<'EOF'

┏━╸┏━┓┏━┓┏┓╻┏━╸╻     ╺┳╸┏━┓   ┏━┓╻  ┏━╸┏━┓╻┏
┃  ┣━┛┣━┫┃┗┫┣╸ ┃      ┃ ┃ ┃   ┣━┛┃  ┣╸ ┗━┓┣┻┓
┗━╸╹  ╹ ╹╹ ╹┗━╸┗━╸    ╹ ┗━┛   ╹  ┗━╸┗━╸┗━┛╹ ╹

     Script to migrate AWStats statistics
            from cPanel to Plesk.
 Forked from plesk/kb-scripts, Edited by Rodri
EOF
}

confirm() {
  local prompt="$1"
  local reply
  read -r -p "$prompt [y/N]: " reply
  echo
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

rename_and_move_txts() {
  local source_dir="$1"
  local target_dir="$2"
  local suffix="$3"
  local kind="$4"
  local search_pattern="$5"
  local dest_domain="$6"
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
    date_part="${base%%\.*}"
    newname="${date_part}.${dest_domain}${suffix}.txt"
    dest="$target_dir/$newname"

    log "Renaming: $base -> $newname"
    log "Moving to: $dest"
    mv -f -- "$file" "$dest"
  done
}

fix_existing_files() {
  local domain="$1"
  local system_dir="/var/www/vhosts/system/$domain"
  
  if [[ ! -d "$system_dir" ]]; then
    die "Destination system directory does not exist: $system_dir"
  fi
  
  for stat_dir in "$system_dir/statistics/webstat" "$system_dir/statistics/webstat-ssl"; do
    if [[ ! -d "$stat_dir" ]]; then
      log "Directory $stat_dir does not exist, skipping"
      continue
    fi
    
    log "Cleaning up files in $stat_dir"
    local all_files=("$stat_dir"/awstats*.txt)
    if (( ${#all_files[@]} == 0 )); then
      log "No .txt files found in $stat_dir"
      continue
    fi
    
    local file base date_part suffix newname
    for file in "${all_files[@]}"; do
      base="$(basename "$file")"
      if [[ "$base" =~ ^(awstats[0-9]{6})\.(.+)-http\.txt$ ]] || [[ "$base" =~ ^(awstats[0-9]{6})\.(.+)-https\.txt$ ]]; then
        date_part="${BASH_REMATCH[1]}"
        suffix="${base##*-}"   # http.txt or https.txt
        suffix="${suffix%.txt}"
        newname="${date_part}.${domain}-${suffix}.txt"
        if [[ "$base" != "$newname" ]]; then
          log "Renaming: $base -> $newname"
          mv -f -- "$file" "$stat_dir/$newname"
        fi
      else
        warn "Skipping file with unexpected format: $base"
      fi
    done
  done
  
  log "Cleanup completed for $domain"
}

# ---------- ARGUMENT PARSING ----------
DOMAIN_DEST=""
DOMAIN_SOURCE=""
SEARCH_OVERRIDE=""
FIX_MODE=0

if [[ $# -eq 0 ]]; then
  usage
  die "Destination domain is required"
fi

if [[ "$1" != "-"* ]]; then
  DOMAIN_DEST="$1"
  shift
fi

# Manual getopt to handle both -f and --fix
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s)
      DOMAIN_SOURCE="$2"
      shift 2
      ;;
    -p)
      SEARCH_OVERRIDE="$2"
      shift 2
      ;;
    -f|--fix)
      FIX_MODE=1
      shift
      ;;
    -h)
      usage
      exit 0
      ;;
    *)
      die "Invalid option: $1"
      ;;
  esac
done

if [[ -z "$DOMAIN_DEST" ]]; then
  usage
  die "You must specify the destination domain as first argument"
fi

# ----- FIX MODE (no necesita source ni migración) -----
if [[ $FIX_MODE -eq 1 ]]; then
  ascii_header
  echo
  log "Fix mode enabled for domain: $DOMAIN_DEST"
  fix_existing_files "$DOMAIN_DEST"
  exit 0
fi

# ----- MODO NORMAL (migración) -----
if [[ -z "$DOMAIN_SOURCE" ]]; then
  DOMAIN_SOURCE="$DOMAIN_DEST"
  log "Option -s not specified, using the same domain as source: $DOMAIN_SOURCE"
fi

ascii_header
echo

log "Destination domain (Plesk): $DOMAIN_DEST"
log "Source domain (tmp):        $DOMAIN_SOURCE"
if [[ -n "$SEARCH_OVERRIDE" ]]; then
  log "Search pattern override:   $SEARCH_OVERRIDE"
fi

log "Searching for source domain root path: $DOMAIN_SOURCE"
SITE_ROOT_SOURCE="$(find_site_root "$DOMAIN_SOURCE")" || die "Could not locate the root path for $DOMAIN_SOURCE (missing httpdocs/tmp?)"

PLESK_SYSTEM_DIR="/var/www/vhosts/system/$DOMAIN_DEST"
if [[ ! -d "$PLESK_SYSTEM_DIR" ]]; then
  die "Destination system directory does not exist: $PLESK_SYSTEM_DIR. Please create the domain/subdomain in Plesk first."
fi

TMP_DIR="$SITE_ROOT_SOURCE/tmp"
CPANEL_AWSTATS_DIR="$TMP_DIR/awstats"
CPANEL_AWSTATS_SSL_DIR="$CPANEL_AWSTATS_DIR/ssl"

PLESK_STATS_DIR="$PLESK_SYSTEM_DIR/statistics/webstat"
PLESK_STATS_SSL_DIR="$PLESK_SYSTEM_DIR/statistics/webstat-ssl"

echo
log "Calculated paths:"
printf '  Source (tmp):          %s\n' "$SITE_ROOT_SOURCE"
printf '  Destination system:    %s\n' "$PLESK_SYSTEM_DIR"
printf '  awstats cPanel:        %s\n' "$CPANEL_AWSTATS_DIR"
printf '  awstats SSL:           %s\n' "$CPANEL_AWSTATS_SSL_DIR"
printf '  Destination HTTP:      %s\n' "$PLESK_STATS_DIR"
printf '  Destination HTTPS:     %s\n' "$PLESK_STATS_SSL_DIR"
echo

if ! confirm "Are these paths correct?"; then
  die "Cancelled by user"
fi

# ---------- PATTERN DETECTION (CORREGIDA) ----------
if [[ -n "$SEARCH_OVERRIDE" ]]; then
  SEARCH_PATTERN="$SEARCH_OVERRIDE"
  log "Using overridden search pattern: $SEARCH_PATTERN"
else
  log "Analyzing available files to determine the correct pattern..."
  SEARCH_PATTERN="$DOMAIN_DEST"
  PATTERN_FOUND=0

  if [[ -d "$CPANEL_AWSTATS_DIR" ]]; then
    shopt -s nullglob
    all_files=("$CPANEL_AWSTATS_DIR"/awstats*.txt)
    shopt -u nullglob
    
    if (( ${#all_files[@]} > 0 )); then
      log "Found ${#all_files[@]} total files"
      
      # 1. Exact match
      for file in "${all_files[@]}"; do
        base="$(basename "$file")"
        pattern="${base#awstats[0-9][0-9][0-9][0-9][0-9][0-9].}"
        pattern="${pattern%.txt}"
        if [[ "$pattern" == "$DOMAIN_DEST" ]]; then
          SEARCH_PATTERN="$pattern"
          PATTERN_FOUND=1
          log "Found exact pattern match: $pattern"
          break
        fi
      done
      
      # 2. Pattern that starts with DOMAIN_DEST + dot
      if [[ $PATTERN_FOUND -eq 0 ]]; then
        for file in "${all_files[@]}"; do
          base="$(basename "$file")"
          pattern="${base#awstats[0-9][0-9][0-9][0-9][0-9][0-9].}"
          pattern="${pattern%.txt}"
          if [[ "$pattern" == "$DOMAIN_DEST".* ]]; then
            SEARCH_PATTERN="$pattern"
            PATTERN_FOUND=1
            log "Found pattern starting with destination domain: $pattern"
            break
          fi
        done
      fi
      
      if [[ $PATTERN_FOUND -eq 0 ]]; then
        warn "Could not find any pattern matching destination domain '$DOMAIN_DEST'"
        warn "Will use destination domain as pattern: $SEARCH_PATTERN"
      fi
    else
      log "No awstats files found in $CPANEL_AWSTATS_DIR"
    fi
  else
    log "Directory $CPANEL_AWSTATS_DIR does not exist"
  fi
fi

log "Final search pattern: $SEARCH_PATTERN"
echo

if ! confirm "Use this pattern to filter files?"; then
  die "Cancelled by user"
fi

# ---------- MIGRATION ----------
log "Preparing HTTP statistics..."
rename_and_move_txts "$CPANEL_AWSTATS_DIR" "$PLESK_STATS_DIR" "-http" "HTTP" "$SEARCH_PATTERN" "$DOMAIN_DEST"

log "Preparing HTTPS statistics..."
rename_and_move_txts "$CPANEL_AWSTATS_SSL_DIR" "$PLESK_STATS_SSL_DIR" "-https" "HTTPS" "$SEARCH_PATTERN" "$DOMAIN_DEST"

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