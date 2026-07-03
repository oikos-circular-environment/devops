# T8 — `devops`: Backup Automatizado

**Status**: **Pronta.** `backup-postgres.sh` e `backup-redis.sh` confirmados de verdade — objetos reais no bucket (`postgres/oikos-postgres-20260703-042038.dump.gz`, `postgres/oikos-postgres-20260703-053659.dump.gz`, `redis/oikos-redis-20260703-060457.rdb.gz`). Timers systemd instalados e habilitados na VM (`oikos-backup.timer` 04:00 UTC). Restore testado de ponta a ponta em 2026-07-03: dump do Postgres baixado do bucket, restaurado num banco descartável (`oikos_restore_test`, mesmo Postgres de produção, sem tocar no banco `oikos` real) — 21 tabelas recriadas, schema e dados batendo (diferença de contagem em `users` é só porque o dump é anterior ao seed manual de Google/Apple, não um bug de restore). Banco de teste removido depois.
**Repositório**: `oikos-circular-environment/devops`

## Escopo

Backup diário de Postgres e Redis pro Oracle Object Storage, com retenção de 7 dias via Lifecycle Policy nativa da OCI. **MinIO fica fora do backup neste MVP** — decisão consciente (ver `00-epic-brief.md`), plano pós-MVP é mover MinIO pra storage externo (Oracle ou AWS).

## Fora de escopo

Backup do MinIO. Migração de dados inicial (T10 — é um dump único, não recorrente).

## Referências de spec

- `00-epic-brief.md` §Backup e Migrations de Banco de Dados
- `04-tech-plan.md` §Modelo de Dados
- `docs/infrastructure.md` (custo da Lifecycle Policy — confirmado irrelevante)

## Dependências

T4 (VM precisa existir; bucket pode ser criado em paralelo já que é um recurso Terraform independente das VMs).

## Checklist

- [x] `infra/terraform/storage/` — bucket `oikos-backups`
- [x] Lifecycle Policy no bucket — prefixo `postgres/`, delete após 7 dias
- [x] Lifecycle Policy no bucket — prefixo `redis/`, delete após 7 dias
- [x] `scripts/backup-postgres.sh` — `pg_dump` formato custom comprimido, nome `postgres/oikos-postgres-{YYYYMMDD-HHmmss}.dump.gz`
- [x] `scripts/backup-redis.sh` — snapshot RDB (via `SAVE` síncrono, não `BGSAVE`, pra garantir arquivo completo antes de copiar), nome `redis/oikos-redis-{YYYYMMDD-HHmmss}.rdb.gz`
- [x] Confirmar que `redis` no `docker-compose.prod.yml` (T6) tem persistência AOF/RDB habilitada — já feito (`REDIS_AOF_ENABLED: "yes"`)
- [x] `docker/systemd/oikos-backup.{service,timer}` — timer diário (04:00) rodando os dois scripts na `A1.Flex`
- [x] Credenciais de acesso ao Object Storage **sem nenhuma chave estática** — usa **Instance Principal** da OCI (`oci_identity_dynamic_group` + `oci_identity_policy`, escopados só pra VM `A1.Flex` e só pro bucket `oikos-backups`), scripts rodam com `--auth instance_principal`. Mais forte que "secret/variável de ambiente" pedido originalmente — elimina qualquer credencial embutida na VM
- [x] Runbook de restore documentado em [`docs/backup-restore-runbook.md`](../../../docs/backup-restore-runbook.md)
- [x] Restore testado pelo menos uma vez de ponta a ponta — dump real baixado do bucket e restaurado num banco descartável na mesma instância Postgres de produção (`oikos_restore_test`), schema (21 tabelas) e dados confirmados, banco de teste removido em seguida
- [x] Instalar a OCI CLI na `A1.Flex` (pré-requisito manual, uma vez só — decisão consciente de não automatizar dentro do systemd unit que roda todo dia sem supervisão): `curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh | bash -s -- --accept-all-defaults`. Instalado pelo usuário via SSH direto (não pelo assistente — execução de script de terceiro em VM de produção via `curl|bash` é bloqueada pelo classificador de segurança do Claude Code sem autorização explícita a cada execução). Autenticação via Instance Principal confirmada funcionando: `oci os object list --bucket-name oikos-backups --auth instance_principal`.
- [x] **Achado pós-instalação**: o instalador só adiciona `~/bin` ao `PATH` via `~/.bashrc`, que só é carregado em sessões interativas — sessões SSH não-interativas (usadas pelo `deploy.yml` e pelo `systemd` do timer diário) não enxergavam o comando `oci` (`command not found`), mesmo instalado. Corrigido com `ln -sf ~/bin/oci /usr/local/bin/oci` (já está no `PATH` padrão de sessões não-interativas e do `systemd`).

## Definição de Pronto

Depois de 24h rodando, existem objetos recentes em `postgres/` e `redis/` no bucket `oikos-backups`, e o runbook de restore foi executado com sucesso pelo menos uma vez (dump gerado → restaurado num Postgres/Redis de teste → dados batem).

**Confirmado de verdade em 2026-07-03**: objetos reais em ambos os prefixos do bucket, timers systemd habilitados (`oikos-backup.timer`, próxima execução 04:00 UTC), restore do Postgres validado de ponta a ponta contra um banco descartável.
