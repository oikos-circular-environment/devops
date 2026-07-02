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
- [ ] Confirmar que o backup automatizado (T8) já gerou pelo menos 1 backup válido na VM Oracle antes do corte
- [ ] Confirmar DNS (T5) resolvendo pra VM Oracle e respondendo corretamente antes do corte oficial
- [ ] Rodar a migração de dados (dump/restore + mirror) num horário de baixo tráfego
- [ ] Validar dados na VM Oracle batem com a origem (contagem de registros, alguns registros de amostra, contagem de objetos MinIO)
- [ ] Apontar o app mobile (ou confirmar que já aponta) pro hostname de produção definitivo
- [ ] Desativar o túnel Cloudflare manual atual (`cloudflared tunnel run --token ...`) na máquina de desenvolvimento
- [ ] Monitorar Grafana (T7) nas primeiras horas pós-corte por qualquer anomalia

## Definição de Pronto

Tráfego real do app mobile passa 100% pela VM Oracle, com dados íntegros migrados, o túnel manual antigo está desligado, e a máquina de desenvolvimento não hospeda mais nenhuma parte da "produção".
