#!/usr/bin/env bash
set -euo pipefail

# Backup diario do Postgres pro Oracle Object Storage (T8). Roda na A1.Flex
# via systemd timer (docker/systemd/oikos-backup.timer). Autentica no Object
# Storage via instance principal - sem nenhuma credencial estatica na VM,
# a OCI CLI precisa estar instalada (ver docker/systemd/oikos-backup.service).

COMPOSE_DIR="/opt/oikos/docker"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.prod.yml"
BUCKET="oikos-backups"

# set -a exporta as variaveis pro ambiente do processo, nao so pro shell
# atual - sem isso, docker compose (processo filho) nao enxerga nenhuma
# delas (achado no teste real do T9: exec falhava com "no password supplied"
# mesmo com o arquivo sourced corretamente).
set -a
# shellcheck disable=SC1091
source "${COMPOSE_DIR}/.env.prod"
set +a

timestamp=$(date -u +%Y%m%d-%H%M%S)
dump_file="/tmp/oikos-postgres-${timestamp}.dump.gz"
object_name="postgres/oikos-postgres-${timestamp}.dump.gz"

# pg_dump nao aceita senha como argumento (por design) - precisa da env var
# PGPASSWORD explicita no processo exec'ado dentro do container.
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
