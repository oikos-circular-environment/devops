#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/bin:$PATH"

COMPOSE_DIR="/opt/oikos/docker"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.prod.yml"
BUCKET="oikos-backups"

set -a
source "${COMPOSE_DIR}/.env.prod"
set +a

timestamp=$(date -u +%Y%m%d-%H%M%S)
dump_file="/tmp/oikos-postgres-${timestamp}.dump.gz"
object_name="postgres/oikos-postgres-${timestamp}.dump.gz"

docker compose --env-file "${COMPOSE_DIR}/.env.prod" -f "$COMPOSE_FILE" exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" postgresql \
  pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB" | gzip > "$dump_file"

oci os object put \
  --bucket-name "$BUCKET" \
  --file "$dump_file" \
  --name "$object_name" \
  --auth instance_principal \
  --force

rm -f "$dump_file"

echo "Backup Postgres concluido: ${object_name}"
