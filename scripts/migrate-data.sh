#!/usr/bin/env bash
set -euo pipefail

# Migracao one-time de dados (Postgres + MinIO) - ver docs/docker-infra.md#8 (ticket 10)
#
# Nenhuma variavel tem default de proposito - forca conferir os valores
# antes de rodar uma operacao dessas, que sobrescreve o banco/bucket de
# destino.
#
# Variaveis de ambiente esperadas:
#   SOURCE_PG_HOST, SOURCE_PG_PORT, SOURCE_PG_USER, SOURCE_PG_PASSWORD, SOURCE_PG_DB
#   SOURCE_MC_ALIAS      - alias mc ja configurado (mc alias set) apontando pro MinIO de origem
#   DEST_SSH_HOST        - IP publico da A1.Flex
#   DEST_SSH_KEY         - caminho da chave privada do usuario deploy
#   DEST_MINIO_PORT      - porta local de MinIO na VM (padrao 9000, so acessivel via IP privado/tunel)
#   DEST_MINIO_ACCESS_KEY, DEST_MINIO_SECRET_KEY - credenciais do MinIO de destino (mesmas do .env.prod da VM)
#
# Uso:
#   ./scripts/migrate-data.sh postgres   # so dump/restore do Postgres
#   ./scripts/migrate-data.sh minio      # so mc mirror dos buckets
#   ./scripts/migrate-data.sh all        # os dois, nessa ordem (default)

MODE="${1:-all}"
DEST_COMPOSE_DIR="/opt/oikos/docker"
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)

require_env() {
  local missing=0
  for var in "$@"; do
    if [ -z "${!var:-}" ]; then
      echo "ERRO: variavel de ambiente obrigatoria nao definida: $var" >&2
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || exit 1
}

migrate_postgres() {
  require_env SOURCE_PG_HOST SOURCE_PG_PORT SOURCE_PG_USER SOURCE_PG_PASSWORD SOURCE_PG_DB DEST_SSH_HOST DEST_SSH_KEY

  local dump_file="/tmp/oikos-migrate-${TIMESTAMP}.dump"

  echo "==> Dump do Postgres de origem (${SOURCE_PG_HOST}:${SOURCE_PG_PORT}/${SOURCE_PG_DB})"
  PGPASSWORD="$SOURCE_PG_PASSWORD" pg_dump \
    -h "$SOURCE_PG_HOST" -p "$SOURCE_PG_PORT" -U "$SOURCE_PG_USER" \
    -Fc "$SOURCE_PG_DB" > "$dump_file"

  echo "==> Copiando dump pra VM Oracle"
  scp -i "$DEST_SSH_KEY" "$dump_file" "deploy@${DEST_SSH_HOST}:/tmp/oikos-migrate.dump"

  echo "==> Restaurando no Postgres da VM Oracle (banco ja deve existir e estar vazio - primeiro cutover)"
  ssh -i "$DEST_SSH_KEY" "deploy@${DEST_SSH_HOST}" "
    set -euo pipefail
    cd ${DEST_COMPOSE_DIR}
    docker compose -f docker-compose.prod.yml cp /tmp/oikos-migrate.dump postgresql:/tmp/restore.dump
    docker compose -f docker-compose.prod.yml exec -T postgresql \
      pg_restore -U \"\${POSTGRES_USER}\" -d \"\${POSTGRES_DB}\" --no-owner --role=\"\${POSTGRES_USER}\" /tmp/restore.dump
    docker compose -f docker-compose.prod.yml exec -T postgresql rm -f /tmp/restore.dump
    rm -f /tmp/oikos-migrate.dump
  "

  echo "==> Rodando prisma migrate deploy pra garantir schema atualizado"
  ssh -i "$DEST_SSH_KEY" "deploy@${DEST_SSH_HOST}" "
    cd ${DEST_COMPOSE_DIR} && docker compose -f docker-compose.prod.yml run --rm api npx prisma migrate deploy
  "

  rm -f "$dump_file"
  echo "==> Postgres migrado."
}

migrate_minio() {
  require_env SOURCE_MC_ALIAS DEST_SSH_HOST DEST_SSH_KEY DEST_MINIO_ACCESS_KEY DEST_MINIO_SECRET_KEY
  DEST_MINIO_PORT="${DEST_MINIO_PORT:-9000}"

  command -v mc >/dev/null || { echo "ERRO: mc (MinIO client) nao encontrado no PATH" >&2; exit 1; }

  echo "==> Abrindo tunel SSH local pro MinIO da VM (porta 9000 nunca e exposta publicamente, ver ticket 06)"
  ssh -i "$DEST_SSH_KEY" -f -N -L "${DEST_MINIO_PORT}:localhost:${DEST_MINIO_PORT}" "deploy@${DEST_SSH_HOST}"
  tunnel_pid=$(pgrep -f "L ${DEST_MINIO_PORT}:localhost:${DEST_MINIO_PORT}.*${DEST_SSH_HOST}" | head -1 || true)
  trap '[ -n "${tunnel_pid:-}" ] && kill "$tunnel_pid" 2>/dev/null || true' EXIT

  echo "==> Configurando alias mc pro destino (via tunel local)"
  mc alias set oikos-dest "http://localhost:${DEST_MINIO_PORT}" "$DEST_MINIO_ACCESS_KEY" "$DEST_MINIO_SECRET_KEY"

  echo "==> Espelhando buckets (mc mirror, origem -> destino)"
  mc mirror --overwrite "${SOURCE_MC_ALIAS}/oikos" "oikos-dest/oikos"

  echo "==> MinIO migrado."
}

case "$MODE" in
  postgres) migrate_postgres ;;
  minio) migrate_minio ;;
  all)
    migrate_postgres
    migrate_minio
    ;;
  *)
    echo "Uso: $0 [postgres|minio|all]" >&2
    exit 1
    ;;
esac
