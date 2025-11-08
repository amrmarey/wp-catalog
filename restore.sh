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
Usage: $0 [--db <db_dump.sql.gz>] [--wp <wp_archive.tar.gz>] [--all <TIMESTAMP>]

Options:
  --db <file>     Restore database from a SQL (gzipped or plain) file path (absolute or relative)
  --wp <file>     Restore WordPress files from a tar.gz archive
  --all <TIMESTAMP>  Restore both DB and WP using files named db_<TIMESTAMP>.sql.gz and wp_<TIMESTAMP>.tar.gz in \$BACKUP_PATH
  --help          Show this help message

Examples:
  $0 --db "$BACKUP_PATH/db_2025-11-08-1200.sql.gz"
  $0 --wp "$BACKUP_PATH/wp_2025-11-08-1200.tar.gz"
  $0 --all 2025-11-08-1200
EOF
}

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

DB_FILE=""
WP_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --db)
      shift; DB_FILE="$1"; shift; ;;
    --wp)
      shift; WP_FILE="$1"; shift; ;;
    --all)
      shift; TS="$1"; DB_FILE="$BACKUP_PATH/db_${TS}.sql.gz"; WP_FILE="$BACKUP_PATH/wp_${TS}.tar.gz"; shift; ;;
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

# Helper: restore DB from file (gzipped or plain)
restore_db(){
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "DB file not found: $file" >&2; exit 3
  fi
  echo "🔁 Restoring database from '$file' into '$DB_NAME'..."
  # Stream into MySQL inside the db container
  if [[ "$file" =~ \.gz$ ]]; then
    gunzip -c "$file" | docker compose exec -T db sh -c "exec mysql -u\"$DB_USER\" -p\"$DB_PASSWORD\" \"$DB_NAME\""
  else
    docker compose exec -T db sh -c "exec mysql -u\"$DB_USER\" -p\"$DB_PASSWORD\" \"$DB_NAME\"" < "$file"
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
  docker compose cp wordpress:/var/www/html "$TMP_PRE/html"
  tar -C "$TMP_PRE" -czf "$PRE_SNAPSHOT" html
  rm -rf "$TMP_PRE"

  # Stop wordpress container to avoid conflicts
  echo " - Stopping wordpress container"
  docker compose stop wordpress || true

  # Extract the provided archive into a temp dir
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  tar -C "$TMP_DIR" -xzf "$file"

  # Remove current files inside container (careful)
  echo " - Removing current /var/www/html contents inside container"
  docker compose exec wordpress sh -c "rm -rf /var/www/html/* || true"

  # Copy restored files into container
  echo " - Copying files into wordpress container"
  # docker cp from host to container
  docker compose cp "$TMP_DIR/html/." wordpress:/var/www/html

  # Start wordpress container
  echo " - Starting wordpress container"
  docker compose start wordpress

  echo "✅ WordPress files restored."
}

# Run requested restores
if [ -n "$DB_FILE" ]; then
  restore_db "$DB_FILE"
fi

if [ -n "$WP_FILE" ]; then
  restore_wp "$WP_FILE"
fi

if [ -z "$DB_FILE" ] && [ -z "$WP_FILE" ]; then
  echo "Nothing to do. Provide --db, --wp, or --all." >&2
  usage
  exit 1
fi

exit 0
