# T01 — Salvaguarda dos dados de produção

**Status**: não iniciada.
**Repositório**: `devops` (execução manual, nada versionado)
**Bloqueia**: [T07](./07-teardown-rebuild.md)

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

## Checklist

- [ ] Dump do Postgres: `pg_dump -Fc` via `docker compose exec`, comprimido, baixado para máquina local (fora da VM)
- [ ] Dump do Redis: `SAVE` síncrono (não `BGSAVE`) + cópia do `dump.rdb`, baixado para máquina local
- [ ] Cópia do bucket do MinIO (`oikos`) para máquina local
- [ ] Conferir tamanho e integridade dos três artefatos (não confiar em "o comando não deu erro")
- [ ] **Restore validado**: subir um Postgres descartável local, restaurar o dump, conferir contagem de tabelas e amostragem de dados
- [ ] Registrar aqui onde os artefatos ficaram guardados e a data/hora do dump

## Definição de Pronto

Os três dumps existem fora da VM, e o restore do Postgres foi executado de ponta a ponta num banco descartável com os dados conferidos. Sem esse aceite explícito, [T07](./07-teardown-rebuild.md) não roda.

## Registro de execução

_(preencher durante a execução)_
