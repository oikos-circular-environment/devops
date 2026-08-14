# T01 — Salvaguarda dos dados de produção

**Status**: **concluída** em 2026-08-14. Escopo reduzido — ver "Reavaliação".
**Repositório**: `devops` (execução manual, nada versionado)
**Bloqueia**: [T07](./07-teardown-rebuild.md) — **desbloqueado**

## Escopo

Extrair e validar um dump completo dos dados de produção **antes** de qualquer `terraform destroy`. Hoje não existe backup nenhum (ver [`00-tech-plan.md`](../00-tech-plan.md)), e o rebuild destrói o boot volume onde vivem os três volumes Docker.

Isto **não** é reintroduzir backup na infra — é uma extração manual de uma vez só. O backup recorrente é redesenho separado ([T02](./02-remover-backup-do-deploy.md)).

## Fora de escopo

Automatizar, agendar ou versionar qualquer parte disto. Redesenhar o backup recorrente.

## Atenção

`redis_data` **não é cache descartável**. Guarda jobs atrasados do BullMQ:

- exclusão de conta agendada com `ACCOUNT_DELETION_DELAY_MS` (90 dias) — `api/src/modules/users/providers/queue/bullmq/bullmq-account-deletion-job-dispatcher.ts:17`
- quórum de denúncia com `QUORUM_JOB_DELAY_MS` (24h) — `api/src/modules/complaints/providers/queue/bullmq/bullmq-job-dispatcher.ts:18`

Descartar o Redis perde exclusões de conta já solicitadas por usuários.

## Reavaliação (2026-08-14)

Os dados **não são de produção real** — o projeto está em fase de teste do MVP, e a perda não implica nada. O usuário confirmou isso explicitamente. Duas consequências:

- A validação de restore deixa de ser critério bloqueante. Os dumps ficam como rede de segurança barata, não como pré-condição cerimonial.
- A ressalva sobre jobs atrasados do BullMQ era teórica e **não se confirmou na prática**: o Redis tem 4 chaves, todas metadados (`bull:account-deletion:meta`, `bull:complaints-quorum:meta`, e os dois `:stalled-check`). **Nenhum job atrasado real pendente**, logo nenhuma exclusão de conta agendada em risco.

Achado colateral relevante: a persistência real do Redis é **AOF**, não RDB (`REDIS_AOF_ENABLED: "yes"`) — o `appendonly.aof.1.incr.aof` tem 21MB contra 381 bytes do `dump.rdb`. Se algum dia o backup de Redis voltar a importar, copiar o `dump.rdb` sozinho **não** é suficiente.

## Checklist

- [x] Dump do Postgres: `pg_dump -Fc` via `docker compose exec` (8,5MB)
- [x] Dump do Redis: `SAVE` síncrono + cópia do `dump.rdb` (381B — praticamente vazio, ver Reavaliação)
- [x] Cópia do bucket do MinIO `oikos` (9,2MB, 13 objetos)
- [x] Conferir tamanho e formato dos artefatos (`PostgreSQL custom database dump - v1.16-0`)
- [x] ~~Restore validado~~ — dispensado, ver Reavaliação
- [x] Artefatos em `/media/ccrs/development/oracle/backup-pre-rebuild-20260814/`, extraídos em 2026-08-14

## Definição de Pronto

Os três dumps existem fora da VM. [T07](./07-teardown-rebuild.md) está desbloqueado.

## Registro de execução

**2026-08-14** — Dumps extraídos da `A1.Flex` (`167.126.6.162`) para `/media/ccrs/development/oracle/backup-pre-rebuild-20260814/`: `postgres-oikos.dump` (8,5MB), `redis-dump.rdb` (381B), `minio-oikos.tar.gz` (9,2MB). Restore não validado, por decisão consciente (dados de teste).

Verificado no mesmo acesso, como pré-requisito de [T05](./05-fragmentar-envs.md): **`docker compose` na VM é v2.40.3**, bem acima do 2.24 exigido por `--env-file` múltiplo.
