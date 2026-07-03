# T10 — `devops`: Migração de Dados + Cutover

**Status**: Escrito e validado localmente (`bash -n`), na branch `feature/t10-migracao-dados`. A execução real (dump/restore/mirror contra dados de verdade) só faz sentido depois de T5/T8/T9 estarem validados na infra real — deferido pra revisão final (ticket 99).
**Repositório**: `oikos-circular-environment/devops`

## Escopo

Migração única dos dados de produção (Postgres + MinIO) da máquina de desenvolvimento atual pra VM Oracle, e o corte final — desativação do túnel Cloudflare manual, tráfego real passando a ir pra infraestrutura nova.

## Fora de escopo

Backup recorrente (T8) — aqui é só a migração inicial, uso único, feito manualmente/assistido (não é um workflow automatizado).

## Referências de spec

- `00-epic-brief.md` §Contexto & Problema (Resultado esperado), §Decisão de Arquitetura (Migração de dados)
- `04-tech-plan.md`

## Dependências

T9 (stack precisa estar rodando de ponta a ponta na VM), T5 (DNS precisa estar pronto pro corte), T8 (backup automatizado já rodando, como rede de segurança antes do corte).

## Checklist

- [x] `scripts/migrate-data.sh` — dump do Postgres da máquina atual (`pg_dump` via rede, parametrizado por `SOURCE_PG_*`)
- [x] `scripts/migrate-data.sh` — restore do dump no Postgres da VM Oracle (copia via `docker compose cp` + `pg_restore` + `prisma migrate deploy`)
- [x] `scripts/migrate-data.sh` — `mc mirror` dos buckets MinIO da máquina atual pra VM Oracle (via túnel SSH local, já que a porta 9000 do MinIO nunca é exposta publicamente — T6)
- [x] Checklist de baixo downtime documentado em [`docs/cutover-checklist.md`](../../../docs/cutover-checklist.md) (ordem exata das operações, janela estimada ~30-60min, rollback)
- [x] Confirmar que o backup automatizado (T8) já gerou pelo menos 1 backup válido na VM Oracle antes do corte — confirmado via `oci os object list --bucket-name oikos-backups` (2026-07-03): dump do Postgres real (04:20 UTC, do timer) + backup do Redis (06:05 UTC). Timer só rodou uma vez até agora (VM provisionada recentemente, ainda sem um segundo ciclo de 24h) — considerado suficiente pelo usuário
- [x] Confirmar DNS (T5) resolvendo pra VM Oracle e respondendo corretamente antes do corte oficial — confirmado via internet real (2026-07-03): `oikos.company`/`www.oikos.company`/`api.oikos.company` respondendo certo
- [~] ~~Rodar a migração de dados (dump/restore + mirror) num horário de baixo tráfego~~ — skip (decisão do usuário, 2026-07-03)
- [~] ~~Validar dados na VM Oracle batem com a origem (contagem de registros, alguns registros de amostra, contagem de objetos MinIO)~~ — skip (decisão do usuário, 2026-07-03)
- [x] Apontar o app mobile (ou confirmar que já aponta) pro hostname de produção definitivo
- [x] Desativar o túnel Cloudflare manual atual (`cloudflared tunnel run --token ...`) na máquina de desenvolvimento — túnel já excluído
- [x] Monitorar Grafana (T7) nas primeiras horas pós-corte por qualquer anomalia — **achado real**: container do Postgres em ~100% de CPU (2026-07-03). Investigado via SSH direto (`docker stats`, `pg_stat_activity`, `/sys/fs/cgroup/cpu.stat`): não era query travada — `nr_throttled` mostrou 99% dos períodos de CPU throttled no limite de `cpus: "1.0"`, Postgres 18 usa `io_method=worker` por padrão (processos extras), e a soma dos `cpus:` de todos os serviços já passava de 4.1 vCPU numa VM de 2 OCPU. Corrigido no código (`docker/docker-compose.prod.yml`): `cpus` do postgres 1.0→1.5, `io_method=sync` (volta ao método clássico pré-PG18), `log_min_duration_statement=200` (queries lentas passam a ser logadas). Também achado processo zumbi `createdb ... oikos_restore_test` (do teste de restore do T8) rodando desde as 04:20 sem nunca finalizar — não foi morto ainda (bloqueado pelo classificador de segurança do Claude Code como escrita destrutiva num host de produção; matar precisa ser feito pelo usuário ou por deploy que reinicie o container).
- [x] **Achado adicional na mesma investigação**: log de query do Postgres não chegava no Loki — só o `api` fala OTLP direto, Postgres nunca teve esse caminho. Corrigido no código: `discovery.docker` + `loki.source.docker` no `alloy-prod.alloy`, escopado só pro container do Postgres (não vira "tail de tudo", mantém a decisão consciente de OTLP-only pra serviços que falam OTLP nativamente). Requer bind mount de `/var/run/docker.sock` (só leitura) no serviço `alloy` do compose — já adicionado.

## Definição de Pronto

Tráfego real do app mobile passa 100% pela VM Oracle, com dados íntegros migrados, o túnel manual antigo está desligado, e a máquina de desenvolvimento não hospeda mais nenhuma parte da "produção".
