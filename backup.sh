#!/usr/bin/env bash
set -euo pipefail

# Enhanced backup.sh
# - Sources .env if present
# - Backs up MySQL via mysqldump
# - Archives all Docker volumes referenced in docker-compose.yml (and top-level volumes)
# - Saves docker inspect and logs for all services
# - Prunes old backups according to BACKUP_RETENTION_DAYS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

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
command -v docker-compose >/dev/null 2>&1 || true

# Determine compose project services
SERVICES=""
if docker compose version >/dev/null 2>&1; then
  SERVICES=$(docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null || true)
else
  # fallback to docker-compose (legacy)
  SERVICES=$(docker-compose -f "$COMPOSE_FILE" config --services 2>/dev/null || true)
fi

# Save inspect and logs for each service
if [ -n "$SERVICES" ]; then
  echo "🔍 Saving inspect and logs for services: $SERVICES"
  for svc in $SERVICES; do
    # Save inspect
    INSPECT_FILE="$BACKUP_PATH/${svc}_${DATE}.inspect.json"
    if docker inspect "$svc" >/dev/null 2>&1; then
      docker inspect "$svc" > "$INSPECT_FILE" || true
    else
      # try with compose service container id
      CID=$(docker compose -f "$COMPOSE_FILE" ps -q "$svc" 2>/dev/null || true)
      if [ -n "$CID" ]; then
        docker inspect "$CID" > "$INSPECT_FILE" || true
      else
        echo " - Could not inspect service/container for $svc"
      fi
    fi

    # Save logs (best effort)
    LOG_FILE="$BACKUP_PATH/${svc}_${DATE}.log"
    docker compose -f "$COMPOSE_FILE" logs --no-color "$svc" > "$LOG_FILE" 2>&1 || true
  done
fi

# Collect volume names referenced in docker-compose.yml
VOLUMES=()
if [ -f "$COMPOSE_FILE" ]; then
  # Top-level declared volumes
  mapfile -t TOPLEVEL < <(awk '/^volumes:/ {p=1; next} p && NF && $1~/^[[:alnum:]_\\-]+:/{gsub(/:/,"",$1); print $1} p && NF==0{exit}' "$COMPOSE_FILE" || true)
  for v in "${TOPLEVEL[@]:-}"; do
    [ -n "$v" ] && VOLUMES+=("$v")
  done

  # Named volumes used in service mounts (pattern: name:/path)
  mapfile -t USED < <(grep -oE "[[:alnum:]_\\-]+:(/|\\.\\.)" "$COMPOSE_FILE" | sed -E 's/:.*$//' || true)
  for v in "${USED[@]:-}"; do
    [ -n "$v" ] && VOLUMES+=("$v")
  done
fi

# Include volumes provided via .env (WP_VOLUME_NAME, DB_VOLUME_NAME)
if [ -n "${WP_VOLUME_NAME:-}" ]; then
  VOLUMES+=("${WP_VOLUME_NAME}")
fi
if [ -n "${DB_VOLUME_NAME:-}" ]; then
  VOLUMES+=("${DB_VOLUME_NAME}")
fi

# Deduplicate volumes
if [ ${#VOLUMES[@]} -gt 0 ]; then
  # Use associative array to dedupe
  declare -A seen
  UNIQUE=()
  for vol in "${VOLUMES[@]}"; do
    if [ -n "$vol" ] && [ -z "${seen[$vol]:-}" ]; then
      seen[$vol]=1
      UNIQUE+=("$vol")
    fi
  done
  VOLUMES=("${UNIQUE[@]}")
fi

# Backup DB via mysqldump (logical backup)
DB_NAME="${WP_DB_NAME:-${MYSQL_DATABASE:-wp_catalog}}"
DB_USER="${WP_DB_USER:-${MYSQL_USER:-wpuser}}"
DB_PASSWORD="${WP_DB_PASSWORD:-${MYSQL_PASSWORD:-}}"
DB_DUMP_FILE="$BACKUP_PATH/db_${DATE}.sql.gz"

echo "📦 Backing up database '$DB_NAME' to $DB_DUMP_FILE"
# Use compose service name if provided in .env
COMPOSE_DB_SERVICE="${COMPOSE_DB_SERVICE:-db}"

docker compose -f "$COMPOSE_FILE" exec -T "$COMPOSE_DB_SERVICE" sh -c "exec mysqldump -u\"$DB_USER\" -p\"$DB_PASSWORD\" \"$DB_NAME\"" | gzip > "$DB_DUMP_FILE" || {
  echo "mysqldump via docker compose failed; trying docker exec by container id..." >&2
  CID=$(docker compose -f "$COMPOSE_FILE" ps -q "$COMPOSE_DB_SERVICE" 2>/dev/null || true)
  if [ -n "$CID" ]; then
    docker exec "$CID" sh -c "exec mysqldump -u\"$DB_USER\" -p\"$DB_PASSWORD\" \"$DB_NAME\"" | gzip > "$DB_DUMP_FILE"
  else
    echo "Failed to locate DB container to run mysqldump" >&2
  fi
}

# Archive each discovered volume using Docker recommended method
if [ ${#VOLUMES[@]} -gt 0 ]; then
  echo "📂 Archiving volumes: ${VOLUMES[*]}"
  for vol in "${VOLUMES[@]}"; do
    OUT="$BACKUP_PATH/${vol}_${DATE}.tar.gz"
    echo " - Archiving volume '$vol' -> $OUT"
    docker run --rm -v "${vol}:/volume" -v "$BACKUP_PATH:/backup" alpine:3.18 sh -c "cd /volume && tar czf /backup/$(basename '$OUT') ." || \
      echo "   Warning: failed to archive volume $vol"
  done
else
  echo "No volumes discovered in compose file or .env."
fi

# Also save docker-compose config for reference
if [ -f "$COMPOSE_FILE" ]; then
  docker compose -f "$COMPOSE_FILE" config > "$BACKUP_PATH/compose_config_${DATE}.yaml" 2>/dev/null || true
fi

# Prune old backups
if [ -n "$BACKUP_RETENTION_DAYS" ] && [ "$BACKUP_RETENTION_DAYS" -gt 0 ]; then
  echo "🧹 Removing backups older than $BACKUP_RETENTION_DAYS days..."
  find "$BACKUP_PATH" -type f -mtime +"$BACKUP_RETENTION_DAYS" -print -delete || true
fi

echo "✅ Backup finished. Files in: $BACKUP_PATH"
exit 0
