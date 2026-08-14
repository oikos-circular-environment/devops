# T02 — Tirar backup do caminho de deploy

**Status**: não iniciada.
**Repositório**: `devops`
**Resolve**: [devops#76](https://github.com/oikos-circular-environment/devops/issues/76)

## Escopo

O job `api-backup` bloqueia deploy de código que não tem relação nenhuma com backup. Foi assim que a `api` ficou um mês travada na `v0.1.1`. Backup sai do caminho de deploy e passa a ser assunto próprio, redesenhado depois.

## Fora de escopo

Redesenhar o backup. Isso vira issue nova, aberta **antes** de fechar a #76.

## Decisões

- **Manter `infra/terraform/storage/` intacto** (bucket `oikos-backups`, `oci_identity_dynamic_group`, `oci_identity_policy`, lifecycle). O caro de recriar depois é o IAM escopado ao OCID da instância, não o bucket — e o bucket vazio custa zero. Desmontar agora é retrabalho garantido no redesenho.
- **Dois commits separados**: primeiro tira do workflow, depois remove scripts e units. Assim dá pra reverter só o segundo se precisar rodar um backup manual de emergência enquanto o redesenho não chega.

## Checklist

- [ ] Remover o job `api-backup` de `.github/workflows/deploy.yml`; `api-migrate` passa a depender de `api-sync`
- [ ] Remover o step condicional de backup (`if: steps.versions.outputs.api_changed == 'true'`) do job `stack-production`
- [ ] Commit separado: remover `scripts/backup-postgres.sh` e `scripts/backup-redis.sh`
- [ ] Commit separado: remover `docker/systemd/oikos-backup.service` e `docker/systemd/oikos-backup.timer`
- [ ] Abrir issue do redesenho de backup (referenciando este ticket e a #76)
- [ ] Atualizar `docs/docker-infra.md` §7 — a seção descreve um backup que não está no ar
- [ ] Corrigir `plans/oracle-cloud-migration/tickets/08-backup-automatizado.md`, que hoje afirma "Pronta" e "timers systemd instalados e habilitados" — factualmente falso desde o redeploy da VM
- [ ] Fechar a #76 referenciando o redesenho

## Definição de Pronto

Um deploy de `api` chega até `api-deploy-container` sem passar por nenhum passo de backup, e nenhum doc do repo afirma que existe backup automatizado rodando.

## Registro de execução

_(preencher durante a execução)_
