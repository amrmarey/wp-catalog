#!/usr/bin/env bash
set -euo pipefail

# backup.sh - backup MySQL (via mysqldump) and WordPress files (via Docker volume archive)
# Follows Docker docs: https://docs.docker.com/engine/storage/volumes/#back-up-restore-or-migrate-data-volumes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env if available and export variables
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi

BACKUP_PATH="${BACKUP_PATH:-$SCRIPT_DIR/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

DATE="$(date +%F-%H%M)"

mkdir -p "$BACKUP_PATH"

command -v docker >/dev/null 2>&1 || { echo "docker is required but not installed" >&2; exit 1; }

echo " Backing up database (mysqldump)..."

# Resolve DB settings (support either WP_ or MYSQL_ names)
DB_NAME="${WP_DB_NAME:-${MYSQL_DATABASE:-wp_catalog}}"
DB_USER="${WP_DB_USER:-${MYSQL_USER:-wpuser}}"
DB_PASSWORD="${WP_DB_PASSWORD:-${MYSQL_PASSWORD:-}}"
DB_DUMP_FILE="$BACKUP_PATH/db_${DATE}.sql.gz"

# Run mysqldump inside DB container and compress to host backup path
docker compose exec -T db sh -c "exec mysqldump -u\"$DB_USER\" -p\"$DB_PASSWORD\" \"$DB_NAME\"" | gzip > "$DB_DUMP_FILE"

echo " - Database backup saved to: $DB_DUMP_FILE"

echo " Backing up WordPress volume 'wp_data' using Docker recommended method..."

# Archive the wp_data volume (standard Docker volume backup procedure)
WP_VOLUME_NAME="wp_data"
WP_ARCHIVE_FILE="$BACKUP_PATH/wp_${DATE}.tar.gz"

docker run --rm \
  -v "${WP_VOLUME_NAME}:/volume" \
  -v "${BACKUP_PATH}:/backup" \
  alpine:3.18 sh -c "cd /volume && tar czf /backup/$(basename \"$WP_ARCHIVE_FILE\") ."

echo " - WordPress volume archive saved to: $WP_ARCHIVE_FILE"

# Optionally, if you want to back up the raw MySQL volume (not recommended while DB is running),
# you can uncomment and use the following (stop the DB container first to ensure consistency):
#
# DB_VOLUME_NAME="db_data"
# docker run --rm -v "${DB_VOLUME_NAME}:/volume" -v "${BACKUP_PATH}:/backup" alpine:3.18 sh -c "cd /volume && tar czf /backup/db_volume_${DATE}.tar.gz ."

echo " Backup completed: $BACKUP_PATH"

# Prune old backups
if [ -n "$BACKUP_RETENTION_DAYS" ] && [ "$BACKUP_RETENTION_DAYS" -gt 0 ]; then
  echo " Removing backups older than $BACKUP_RETENTION_DAYS days..."
  find "$BACKUP_PATH" -type f \( -name 'db_*.sql.gz' -o -name 'wp_*.tar.gz' -o -name 'db_volume_*.tar.gz' \) -mtime +"$BACKUP_RETENTION_DAYS" -print -delete || true
fi

exit 0
