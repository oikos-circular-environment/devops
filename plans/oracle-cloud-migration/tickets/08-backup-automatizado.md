# T8 — `devops`: Backup Automatizado

**Status**: Não iniciado
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

- [ ] `infra/terraform/storage/` — bucket `oikos-backups`
- [ ] Lifecycle Policy no bucket — prefixo `postgres/`, delete após 7 dias
- [ ] Lifecycle Policy no bucket — prefixo `redis/`, delete após 7 dias
- [ ] `scripts/backup-postgres.sh` — `pg_dump` formato custom comprimido, nome `postgres/oikos-postgres-{YYYYMMDD-HHmmss}.dump.gz`
- [ ] `scripts/backup-redis.sh` — snapshot RDB, nome `redis/oikos-redis-{YYYYMMDD-HHmmss}.rdb.gz`
- [ ] Confirmar que `redis` no `docker-compose.prod.yml` (T6) tem persistência AOF/RDB habilitada — pré-requisito pro backup fazer sentido
- [ ] Cron/systemd timer diário rodando os dois scripts na `A1.Flex`
- [ ] Credenciais de acesso ao Object Storage (chave da API OCI) disponíveis pro script, sem hardcode — cadastradas como secret/variável de ambiente
- [ ] Runbook de restore documentado (passo a passo pra restaurar Postgres e Redis a partir de um dump do bucket)
- [ ] Restore testado pelo menos uma vez de ponta a ponta (não só geração do backup — a restauração de verdade)

## Definição de Pronto

Depois de 24h rodando, existem objetos recentes em `postgres/` e `redis/` no bucket `oikos-backups`, e o runbook de restore foi executado com sucesso pelo menos uma vez (dump gerado → restaurado num Postgres/Redis de teste → dados batem).
