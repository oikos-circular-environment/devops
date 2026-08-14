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
rdb_file="/tmp/oikos-redis-${timestamp}.rdb"
gz_file="${rdb_file}.gz"
object_name="redis/oikos-redis-${timestamp}.rdb.gz"

docker compose --env-file "${COMPOSE_DIR}/.env.prod" -f "$COMPOSE_FILE" exec -T redis \
  redis-cli -a "$REDIS_PASSWORD" --no-auth-warning SAVE

container_id=$(docker compose --env-file "${COMPOSE_DIR}/.env.prod" -f "$COMPOSE_FILE" ps -q redis)
docker cp "${container_id}:/bitnami/redis/data/dump.rdb" "$rdb_file"
gzip "$rdb_file"

oci os object put \
  --bucket-name "$BUCKET" \
  --file "$gz_file" \
  --name "$object_name" \
  --auth instance_principal \
  --force

rm -f "$gz_file"

echo "Backup Redis concluido: ${object_name}"
