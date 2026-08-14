# T02 — Tirar backup do caminho de deploy

**Status**: **concluída** em 2026-08-14.
**Repositório**: `devops`
**Resolve**: [devops#76](https://github.com/oikos-circular-environment/devops/issues/76) · **Redesenho**: [devops#90](https://github.com/oikos-circular-environment/devops/issues/90)

## Escopo

O job `api-backup` bloqueia deploy de código que não tem relação nenhuma com backup. Foi assim que a `api` ficou um mês travada na `v0.1.1`. Backup sai do caminho de deploy e passa a ser assunto próprio, redesenhado depois.

## Fora de escopo

Redesenhar o backup. Isso vira issue nova, aberta **antes** de fechar a #76.

## Decisões

- **Manter `infra/terraform/storage/` intacto** (bucket `oikos-backups`, `oci_identity_dynamic_group`, `oci_identity_policy`, lifecycle). O caro de recriar depois é o IAM escopado ao OCID da instância, não o bucket — e o bucket vazio custa zero. Desmontar agora é retrabalho garantido no redesenho.
- **Dois commits separados**: primeiro tira do workflow, depois remove scripts e units. Assim dá pra reverter só o segundo se precisar rodar um backup manual de emergência enquanto o redesenho não chega.

## Checklist

- [x] Remover o job `api-backup` de `.github/workflows/deploy.yml`; `api-migrate` passa a depender de `api-sync`
- [x] Remover o step condicional de backup (`if: steps.versions.outputs.api_changed == 'true'`) do job `stack-production`
- [x] Commit separado: remover `scripts/backup-postgres.sh` e `scripts/backup-redis.sh`
- [x] Commit separado: remover `docker/systemd/oikos-backup.service` e `docker/systemd/oikos-backup.timer`
- [x] Abrir issue do redesenho de backup — [devops#90](https://github.com/oikos-circular-environment/devops/issues/90)
- [x] Atualizar `docs/docker-infra.md` §7
- [x] Corrigir `plans/oracle-cloud-migration/tickets/08-backup-automatizado.md`
- [ ] Fechar a #76 (após o merge do PR #89)

## Definição de Pronto

Um deploy de `api` chega até `api-deploy-container` sem passar por nenhum passo de backup, e nenhum doc do repo afirma que existe backup automatizado rodando.

## Registro de execução

**2026-08-14** — Executado. Dois commits separados como planejado (`e1ad150` no workflow, `06911d7` nos scripts/units) mais `3711753` de documentação. Migration preservada nos dois pontos onde existe (`api-migrate` e o step condicional de `stack-production`, que compartilha o gate `api_changed`). Zero referência residual a backup fora de `plans/`.

Achados registrados na #90 para o redesenho:

- A persistência real do Redis é **AOF, não RDB** (`REDIS_AOF_ENABLED: "yes"`): o `appendonly.aof.1.incr.aof` tem 21MB contra 381 bytes do `dump.rdb`. O script removido copiava só o `dump.rdb` — **estava incompleto por desenho**, não apenas quebrado por falta da OCI CLI.
- `rclone` tem backend nativo de OCI Object Storage com `provider = instance_principal_auth` (binário estático único, sem Python/pip), o que evita repetir a dependência de instalação manual que causou a #76.

Nota: o fix de `PATH` da OCI CLI (PR #85, mergeado mais cedo no mesmo dia) virou letra morta — os scripts que ele corrigia foram deletados aqui. Caminho abandonado por remoção, não por correção.
