# Runbook de Restore — Postgres e Redis

Passo a passo pra restaurar um backup do bucket `oikos-backups` (Oracle Object Storage). Referência: [`08-backup-automatizado.md`](../plans/oracle-cloud-migration/tickets/08-backup-automatizado.md).

## Pré-requisito

OCI CLI instalada e autenticada (na `A1.Flex` já usa instance principal automaticamente; rodando de outra máquina, usar `oci session authenticate` como em [`docs/terraform-cloud-credentials-setup.md`](terraform-cloud-credentials-setup.md)).

## Listar backups disponíveis

```bash
oci os object list --bucket-name oikos-backups --prefix postgres/ --auth instance_principal
oci os object list --bucket-name oikos-backups --prefix redis/ --auth instance_principal
```

## Restore do Postgres

1. Baixar o dump escolhido:
   ```bash
   oci os object get --bucket-name oikos-backups --name "postgres/oikos-postgres-<timestamp>.dump.gz" \
     --file /tmp/restore.dump.gz --auth instance_principal
   gunzip /tmp/restore.dump.gz
   ```
2. **Parar a `api`** (evita escrita concorrente durante o restore):
   ```bash
   cd /opt/oikos/docker
   docker compose -f docker-compose.prod.yml stop api
   ```
3. Restaurar num banco de teste primeiro (nunca direto em cima do banco de produção sem validar):
   ```bash
   docker compose -f docker-compose.prod.yml exec -T postgresql \
     createdb -U "$POSTGRES_USER" oikos_restore_test
   docker compose -f docker-compose.prod.yml exec -T postgresql \
     pg_restore -U "$POSTGRES_USER" -d oikos_restore_test < /tmp/restore.dump
   ```
4. Validar os dados no banco de teste (contagem de linhas nas tabelas principais, spot-check de registros recentes).
5. Só depois de validado, restaurar de fato (substitui o banco de produção):
   ```bash
   docker compose -f docker-compose.prod.yml exec -T postgresql \
     dropdb -U "$POSTGRES_USER" "$POSTGRES_DB"
   docker compose -f docker-compose.prod.yml exec -T postgresql \
     createdb -U "$POSTGRES_USER" "$POSTGRES_DB"
   docker compose -f docker-compose.prod.yml exec -T postgresql \
     pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" < /tmp/restore.dump
   ```
6. Rodar `prisma migrate deploy` (garante que o schema restaurado bate com a versão do código em produção):
   ```bash
   docker compose -f docker-compose.prod.yml run --rm api npx prisma migrate deploy
   ```
7. Religar a `api`:
   ```bash
   docker compose -f docker-compose.prod.yml start api
   ```
8. Limpar o banco de teste: `docker compose -f docker-compose.prod.yml exec -T postgresql dropdb -U "$POSTGRES_USER" oikos_restore_test`

## Restore do Redis

Redis é fila de jobs — perder o estado é tolerável (jobs são reenfileirados), mas o restore serve pra recuperar de uma perda total do volume.

1. Baixar e descomprimir:
   ```bash
   oci os object get --bucket-name oikos-backups --name "redis/oikos-redis-<timestamp>.rdb.gz" \
     --file /tmp/restore.rdb.gz --auth instance_principal
   gunzip /tmp/restore.rdb.gz
   ```
2. Parar o Redis:
   ```bash
   cd /opt/oikos/docker
   docker compose -f docker-compose.prod.yml stop redis
   ```
3. Copiar o RDB pro volume do container e subir de novo (Redis carrega o RDB automaticamente no boot):
   ```bash
   docker cp /tmp/restore.rdb "$(docker compose -f docker-compose.prod.yml ps -q redis 2>/dev/null || echo redis_temp)":/bitnami/redis/data/dump.rdb
   docker compose -f docker-compose.prod.yml start redis
   ```
   Se o container não existir ainda (`ps -q` vazio), copiar o arquivo direto no volume nomeado (`redis_data`) antes do primeiro `up`.
4. Validar: `docker compose -f docker-compose.prod.yml exec redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning DBSIZE` (compara com o tamanho esperado).

## Status

- [ ] Executado de ponta a ponta pelo menos uma vez (dump gerado → restaurado num destino de teste → dados batem) — pendente, planejado pra revisão final do épico (ticket `99-review-final.md`), junto com o resto dos testes reais contra a infraestrutura.
