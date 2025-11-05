#!/bin/bash
set -e
DATE=$(date +%F-%H%M)
BACKUP_DIR=./backups

mkdir -p $BACKUP_DIR

echo "📦 Backing up database..."
docker compose exec db \
  mysqldump -u${WP_DB_USER} -p${WP_DB_PASSWORD} ${WP_DB_NAME} > $BACKUP_DIR/db_$DATE.sql

echo "📂 Backing up WordPress files..."
docker compose cp wordpress:/var/www/html $BACKUP_DIR/wp_$DATE

echo "✅ Backup completed: $BACKUP_DIR"
