#!/usr/bin/env bash
set -euo pipefail

# Backup diario do Redis pro Oracle Object Storage (T8) - snapshot RDB via
# SAVE sincrono (nao BGSAVE, pra garantir que o arquivo esta completo antes
# de copiar). Mesmo mecanismo de autenticacao do backup-postgres.sh (instance
# principal).

COMPOSE_DIR="/opt/oikos/docker"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.prod.yml"
BUCKET="oikos-backups"

# shellcheck disable=SC1091
source "${COMPOSE_DIR}/.env.prod"

timestamp=$(date -u +%Y%m%d-%H%M%S)
rdb_file="/tmp/oikos-redis-${timestamp}.rdb"
gz_file="${rdb_file}.gz"
object_name="redis/oikos-redis-${timestamp}.rdb.gz"

docker compose -f "$COMPOSE_FILE" exec -T redis \
  redis-cli -a "$REDIS_PASSWORD" --no-auth-warning SAVE

container_id=$(docker compose -f "$COMPOSE_FILE" ps -q redis)
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
