# v2 da Infra e do CI/CD — Plano Técnico

**Issues**: [devops#76](https://github.com/oikos-circular-environment/devops/issues/76) (backup quebrado no redeploy) e [devops#77](https://github.com/oikos-circular-environment/devops/issues/77) (revisar CI/CD e rebuild da infra).
**Repositório**: `oikos-circular-environment/devops` (com ajustes pontuais em `api` e `web`).

## Por que este plano existe

A `api` em produção está travada na tag `v0.1.1` (deploy de 2026-07-08) enquanto `v0.2.0`, `v0.3.0` e `v0.3.1` já foram buildadas e publicadas no GHCR. Todos os deploys desde então morreram no mesmo ponto:

```
/opt/oikos/scripts/backup-postgres.sh: line 25: oci: command not found
Process completed with exit code 127
```

Como `api-migrate` e `api-deploy-container` dependem de `api-backup` via `needs:`, os dois foram pulados em cadeia e o código nunca chegou na VM.

**Causa raiz confirmada por SSH na `A1.Flex`**: a OCI CLI **não está instalada** (não é problema de `PATH` em shell não-interativo, como parecia à primeira vista — um `find` no disco inteiro não acha o binário), e as units `oikos-backup.*` **nunca foram registradas** em `/etc/systemd/system` (`systemctl list-unit-files 'oikos*'` retorna vazio). Ambas eram passos manuais de uma vez só do [ticket 08 do `oracle-cloud-migration`](../oracle-cloud-migration/tickets/08-backup-automatizado.md), e o redeploy da VM levou as duas embora.

**Consequência silenciosa**: não existe backup de Postgres nem de Redis desde o redeploy. O deploy quebrado foi só o primeiro sintoma visível.

## Levantamento (medido, não o que está nos docs)

| | Realidade medida |
|---|---|
| A1.Flex `oikos-app` | 2 OCPU / 12GB / 145GB — usando 1.3GB de 12GB |
| E2.1.Micro `oikos-observability` | 1 OCPU / 1GB |
| Containers na A1.Flex | 9, todos com `restart: unless-stopped` |
| `.github/workflows/deploy.yml` | 458 linhas, 9 jobs, setup de chave SSH duplicado **7×** |
| `infra/terraform/` | 4 módulos (`network`, `compute`, `dns`, `storage`), ~700 linhas |
| Dados de produção | volumes Docker locais: `postgresql_data`, `redis_data`, `minio_data` |

`docs/infrastructure.md` documenta o Always Free como 2 OCPU/12GB, e é isso que a tenancy tem hoje — a Oracle reduziu o teto de 4 OCPU/24GB para 2 OCPU/12GB em junho/2026, com corte de recursos acima do limite a partir de 18/08/2026. A tenancy está dentro do limite.

## Análise crítica

1. **A premissa "container cai e não se reergue" não se sustenta para o app.** Todos os 9 containers da `A1.Flex` já têm `restart: unless-stopped` em `docker/docker-compose.prod.yml`. O incidente do Tempo (4 dias fora sem ninguém notar) foi no stack de observabilidade, cujo arquivo base tinha `restart: "no"` — problema de configuração e de alerta ausente, não de orquestrador.

2. **Os três incidentes reais foram de provisionamento e de desenho de CI, não de orquestração.** Tempo OOM sem alerta; OCI CLI e systemd sumindo no rebuild; env do `web` presa ao ciclo de release do `api`. Trocar o runtime não resolveria nenhum dos três. Por isso o Docker Compose fica, e o esforço vai para provisionamento declarativo e desacoplamento de pipeline.

3. **O risco real é dado, não uptime.** Os volumes vivem no boot volume da VM, que será destruída no rebuild. E o `redis_data` **não é descartável**: guarda jobs atrasados do BullMQ — exclusão de conta agendada com `ACCOUNT_DELETION_DELAY_MS` (90 dias, `api/src/modules/users/providers/queue/bullmq/bullmq-account-deletion-job-dispatcher.ts:17`) e quórum de denúncia com `QUORUM_JOB_DELAY_MS` (24h, `api/src/modules/complaints/providers/queue/bullmq/bullmq-job-dispatcher.ts:18`). Perder o Redis perde exclusões de conta já solicitadas por usuários.

4. **Segredo duplicado é o preço do desacoplamento.** `CLIENT_KEY_WEB` (lida pelo `api`) e `CLIENT_API_KEY` (lida pelo `web`) são o mesmo valor em containers diferentes. Separar os Environments faz esse valor existir em dois lugares no GitHub, e rotação passa a exigir atualizar os dois em sincronia. Consequência aceita conscientemente.

## Decisões

| Decisão | Racional |
|---|---|
| Runtime continua **Docker Compose** | Nenhum dos incidentes seria evitado por orquestrador; 2 OCPU é teto apertado pra overhead de cluster |
| **Kubernetes fora do plano** | Pesquisado a pedido, avaliado e descartado nesta fase |
| **Nomad + Consul: avaliar depois** | Registrado em [`nomad-consul-avaliacao.md`](./nomad-consul-avaliacao.md), a analisar **após** estas mudanças |
| **Teardown total e rebuild do zero** | Downtime aceito explicitamente; é o que prova que o provisionamento virou declarativo |
| **Backup sai do caminho de deploy** | Redesenho vira issue separada; não bloqueia mais deploy de código |
| CI padronizado só em `api` e `web` | `mobile` tem EAS Workflow e contexto próprios |
| Sem merge automático | PRs abertos para revisão humana; `api#86` não é tocada |

## Sequência

`T01` (salvaguarda de dados) bloqueia `T07` (teardown). `T02`→`T05` são refatorações de pipeline, reversíveis, feitas com produção no ar. `T06` precisa estar pronto antes de `T07`, senão o rebuild não valida nada. `T08` é independente e pode correr em paralelo.

```
T01 ─────────────────────────────────────┐
T02 → T03 → T04 → T05 → T06 → T07 ───────┘
T08 (paralelo)
```

## Tickets

| # | Título | Bloqueia |
|---|---|---|
| [01](./tickets/01-salvaguarda-dados.md) | Salvaguarda dos dados de produção | T07 |
| [02](./tickets/02-remover-backup-do-deploy.md) | Tirar backup do caminho de deploy (#76) | — |
| [03](./tickets/03-composite-actions.md) | Extrair composite actions | T04 |
| [04](./tickets/04-quebrar-deploy-yml.md) | Quebrar o `deploy.yml` em entrypoints | T05 |
| [05](./tickets/05-fragmentar-envs.md) | Fragmentar as envs por dono | — |
| [06](./tickets/06-provisionamento-declarativo.md) | Provisionamento 100% declarativo | T07 |
| [07](./tickets/07-teardown-rebuild.md) | Teardown e rebuild do zero | — |
| [08](./tickets/08-padronizar-ci-api-web.md) | Padronizar CI de `api` e `web` | — |

## Pendência já aberta

PR [devops#88](https://github.com/oikos-circular-environment/devops/pull/88) adiciona `ARG`/`build-args` de `NEXT_PUBLIC_API_URL` e `NEXT_PUBLIC_CLIENT_API_KEY` no build do `web`. Sem ele o `web` quebra assim que `web#50` chegar em produção: `web/src/lib/env.ts` lança exceção se a env faltar, e o Next.js inlina `NEXT_PUBLIC_*` em build time (não em runtime). Falta cadastrar o secret `NEXT_PUBLIC_CLIENT_API_KEY` no Environment `web-production`.
