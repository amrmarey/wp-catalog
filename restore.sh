#!/usr/bin/env bash
set -euo pipefail

# restore.sh - restore database and WordPress files from backups
# Linux-only script
# Usage examples:
#   ./restore.sh --db backups/db_2025-11-08-1200.sql.gz
#   ./restore.sh --wp backups/wp_2025-11-08-1200.tar.gz
#   ./restore.sh --all 2025-11-08-1200   # restores db_... and wp_... by timestamp

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env if available
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi

BACKUP_PATH="${BACKUP_PATH:-./backups}"

usage(){
  cat <<EOF
Usage: $0 [--db <db_dump.sql.gz>] [--db-volume <db_volume_archive.tar.gz>] [--wp <wp_archive.tar.gz>] [--wp-volume <wp_volume_archive.tar.gz>] [--all <TIMESTAMP>]

Options:
  --db <file>         Restore database from a SQL (gzipped or plain) file path (absolute or relative)
  --db-volume <file>  Restore raw DB volume archive into the DB Docker volume (will stop DB service)
  --wp <file>         Restore WordPress files into the container (uses docker compose cp)
  --wp-volume <file>  Restore WordPress volume archive into the configured volume (recommended for full-site restores)
  --all <TIMESTAMP>   Restore both DB and WP using files named db_<TIMESTAMP>.sql.gz and wp_<TIMESTAMP>.tar.gz in \$BACKUP_PATH
  --help              Show this help message

Examples:
  $0 --db "$BACKUP_PATH/db_2025-11-08-1200.sql.gz"
  $0 --wp "$BACKUP_PATH/wp_2025-11-08-1200.tar.gz"
  $0 --wp-volume "$BACKUP_PATH/wp_2025-11-08-1200.tar.gz"
  $0 --all 2025-11-08-1200
EOF
}

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

DB_FILE=""
WP_FILE=""
DB_VOLUME_FILE=""
WP_VOLUME_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --db)
      shift; DB_FILE="$1"; shift; ;;
    --db-volume)
      shift; DB_VOLUME_FILE="$1"; shift; ;;
    --wp)
      shift; WP_FILE="$1"; shift; ;;
    --wp-volume)
      shift; WP_VOLUME_FILE="$1"; shift; ;;
    --all)
      shift; TS="$1";
      DB_FILE="$BACKUP_PATH/db_${TS}.sql.gz";
      # infer volume archives for DB and WP
      DB_VOLUME_FILE="$BACKUP_PATH/${DB_VOLUME_NAME}_${TS}.tar.gz"
      WP_VOLUME_FILE="$BACKUP_PATH/${WP_VOLUME_NAME}_${TS}.tar.gz"
      # also collect any other volume archives matching the timestamp
      shift; ;;
    --help)
      usage; exit 0; ;;
    *)
      echo "Unknown arg: $1" >&2; usage; exit 2; ;;
  esac
done

command -v docker >/dev/null 2>&1 || { echo "docker is required but not installed" >&2; exit 1; }

# Resolve DB settings (support either WP_ or MYSQL_ names)
DB_NAME="${WP_DB_NAME:-${MYSQL_DATABASE:-wp_catalog}}"
DB_USER="${WP_DB_USER:-${MYSQL_USER:-wpuser}}"
DB_PASSWORD="${WP_DB_PASSWORD:-${MYSQL_PASSWORD:-}}"

# Services and volume names from .env (fall back to sensible defaults)
COMPOSE_DB_SERVICE="${COMPOSE_DB_SERVICE:-db}"
COMPOSE_WP_SERVICE="${COMPOSE_WP_SERVICE:-wordpress}"
WP_VOLUME_NAME="${WP_VOLUME_NAME:-wp_data}"
DB_VOLUME_NAME="${DB_VOLUME_NAME:-db_data}"

# Helper: restore DB from file (gzipped or plain)
restore_db(){
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "DB file not found: $file" >&2; exit 3
  fi
  echo "🔁 Restoring database from '$file' into '$DB_NAME'..."
  # Stream into MySQL inside the db container
  if [[ "$file" =~ \.gz$ ]]; then
    gunzip -c "$file" | docker compose -f "$COMPOSE_FILE" exec -T "$COMPOSE_DB_SERVICE" sh -c "exec mysql -u\"$DB_USER\" -p\"$DB_PASSWORD\" \"$DB_NAME\""
  else
    docker compose -f "$COMPOSE_FILE" exec -T "$COMPOSE_DB_SERVICE" sh -c "exec mysql -u\"$DB_USER\" -p\"$DB_PASSWORD\" \"$DB_NAME\"" < "$file"
  fi
  echo "✅ Database restored."
}

# Helper: restore WP files from tar.gz
restore_wp(){
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "WP archive not found: $file" >&2; exit 4
  fi
  echo "🔁 Restoring WordPress files from '$file'..."

  # Create a pre-restore snapshot (safety)
  TS_NOW="$(date +%F-%H%M)"
  PRE_SNAPSHOT="$BACKUP_PATH/pre_restore_wp_${TS_NOW}.tar.gz"
  echo " - Creating pre-restore snapshot to $PRE_SNAPSHOT"
  # Copy current files out of container
  TMP_PRE="$(mktemp -d)"
  trap 'rm -rf "$TMP_PRE"' RETURN
  docker compose -f "$COMPOSE_FILE" cp "$COMPOSE_WP_SERVICE":/var/www/html "$TMP_PRE/html"
  tar -C "$TMP_PRE" -czf "$PRE_SNAPSHOT" html
  rm -rf "$TMP_PRE"

  # Stop wordpress container to avoid conflicts
  echo " - Stopping $COMPOSE_WP_SERVICE container"
  docker compose -f "$COMPOSE_FILE" stop "$COMPOSE_WP_SERVICE" || true

  # Extract the provided archive into a temp dir
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  tar -C "$TMP_DIR" -xzf "$file"

  # Remove current files inside container (careful)
  echo " - Removing current /var/www/html contents inside container"
  docker compose -f "$COMPOSE_FILE" exec "$COMPOSE_WP_SERVICE" sh -c "rm -rf /var/www/html/* || true"

  # Copy restored files into container
  echo " - Copying files into wordpress container"
  # docker cp from host to container
  docker compose -f "$COMPOSE_FILE" cp "$TMP_DIR/html/." "$COMPOSE_WP_SERVICE":/var/www/html

  # Start wordpress container
  echo " - Starting $COMPOSE_WP_SERVICE container"
  docker compose -f "$COMPOSE_FILE" start "$COMPOSE_WP_SERVICE"

  echo "✅ WordPress files restored."
}

## Generic volume restore: infers volume name from archive filename
restore_volume(){
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "Volume archive not found: $file" >&2; return 1
  fi
  FILE_DIR="$(cd "$(dirname "$file")" && pwd)"
  FILE_BASE="$(basename "$file")"

  # infer volume name by removing trailing _YYYY-MM-DD-HHMM.tar.gz
  VNAME=$(echo "$FILE_BASE" | sed -E 's/_([0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4})\.tar\.gz$//')
  if [ -z "$VNAME" ]; then
    echo "Could not infer volume name from filename: $FILE_BASE" >&2; return 2
  fi

  echo "🔁 Restoring volume '$VNAME' from '$file'..."

  # decide if we should stop a service for consistency
  STOPPED_SERVICE=""
  if [ "$VNAME" = "$WP_VOLUME_NAME" ]; then
    STOPPED_SERVICE="$COMPOSE_WP_SERVICE"
  elif [ "$VNAME" = "$DB_VOLUME_NAME" ]; then
    STOPPED_SERVICE="$COMPOSE_DB_SERVICE"
  fi

  if [ -n "$STOPPED_SERVICE" ]; then
  echo " - Stopping $STOPPED_SERVICE to ensure consistency"
  docker compose -f "$COMPOSE_FILE" stop "$STOPPED_SERVICE" || true
  fi

  echo " - Extracting archive into volume using transient container"
  docker run --rm -v "${VNAME}:/volume" -v "${FILE_DIR}:/backup" alpine:3.18 sh -c "cd /volume && tar xzf /backup/${FILE_BASE}"

  if [ -n "$STOPPED_SERVICE" ]; then
  echo " - Starting $STOPPED_SERVICE"
  docker compose -f "$COMPOSE_FILE" start "$STOPPED_SERVICE"
  fi

  echo "✅ Volume $VNAME restored."
  return 0
}

# Backwards-compatible wrappers
restore_wp_volume(){ restore_volume "$1"; }
restore_db_volume(){ restore_volume "$1"; }

# Run requested restores
if [ -n "$DB_FILE" ]; then
  restore_db "$DB_FILE"
fi

if [ -n "$WP_FILE" ]; then
  restore_wp "$WP_FILE"
fi

if [ -n "$WP_VOLUME_FILE" ]; then
  restore_wp_volume "$WP_VOLUME_FILE"
fi
if [ -n "$DB_VOLUME_FILE" ]; then
  restore_db_volume "$DB_VOLUME_FILE"
fi

# If --all was used with a timestamp, also restore any other volume archives that match _<TS>.tar.gz
if [ -n "${TS:-}" ]; then
  echo "Looking for other volume archives matching timestamp $TS in $BACKUP_PATH..."
  while IFS= read -r volfile; do
    [ -z "$volfile" ] && continue
    # skip files already handled
    case "$volfile" in
      *"/${DB_VOLUME_NAME}_$TS.tar.gz"|*"/${WP_VOLUME_NAME}_$TS.tar.gz")
        continue;;
    esac
    echo " - Found volume archive: $volfile"
    restore_volume "$volfile" || echo "   Warning: failed to restore $volfile"
  done < <(find "$BACKUP_PATH" -maxdepth 1 -type f -name "*_${TS}.tar.gz" -print 2>/dev/null || true)
fi

if [ -z "$DB_FILE" ] && [ -z "$DB_VOLUME_FILE" ] && [ -z "$WP_FILE" ] && [ -z "$WP_VOLUME_FILE" ]; then
  echo "Nothing to do. Provide --db, --wp, or --all." >&2
  usage
  exit 1
fi

exit 0
