# Checklist de Cutover — Migração pra VM Oracle (T10)

Ordem exata das operações pro corte final, da máquina de desenvolvimento atual pra VM Oracle (`A1.Flex`). Referência: [`10-migracao-dados-cutover.md`](../plans/oracle-cloud-migration/tickets/10-migracao-dados-cutover.md).

**Janela de corte estimada**: ~30-60min (dump/restore do Postgres é a parte mais demorada; MinIO via `mc mirror` incremental é rápido se já rodou uma vez antes pra aquecer). Fazer num horário de baixo tráfego do app mobile.

## Pré-requisitos (antes do dia do corte)

- [ ] **T5 pronta**: DNS resolvendo `api.oikos.company` e `oikos.company` pra VM Oracle, login próprio funcionando em `grafana`/`minio` — mas **ainda sem tráfego real** (túnel antigo continua sendo a fonte de verdade até o corte)
- [ ] **T8 rodando há pelo menos 24h**: confirmar objetos recentes em `postgres/` e `redis/` no bucket `oikos-backups` — rede de segurança antes de qualquer operação destrutiva
- [ ] **T9 validada**: `workflow_dispatch` manual do `deploy.yml` já rodou com sucesso pelo menos uma vez, stack completa saudável na VM
- [ ] Testar `scripts/migrate-data.sh minio` uma vez **antes** do dia do corte (mirror incremental, não destrutivo) — aquece o cache e valida que o túnel SSH + `mc` funcionam, sem pressa do corte real

## Dia do corte

1. [ ] Avisar (se aplicável) que a janela de manutenção está começando
2. [ ] Colocar a API atual (máquina de desenvolvimento) em modo somente-leitura, se houver esse mecanismo — senão, aceitar a janela curta de escrita perdida entre o dump e o corte de DNS
3. [ ] Rodar `scripts/migrate-data.sh postgres` — dump da origem, restore + `prisma migrate deploy` no destino
4. [ ] Rodar `scripts/migrate-data.sh minio` — mirror final (incremental, já aquecido pelo pré-requisito)
5. [ ] **Validar dados na VM Oracle**:
   - Contagem de linhas nas tabelas principais bate com a origem (`SELECT count(*) FROM <tabela>` nos dois lados)
   - Alguns registros de amostra (os mais recentes) conferidos manualmente
   - Contagem de objetos MinIO bate (`mc ls --recursive oikos-dest/oikos | wc -l` vs. equivalente na origem)
6. [ ] Confirmar a stack de produção saudável na VM (`docker compose --env-file .env.prod -f docker-compose.prod.yml ps`, todos os serviços `healthy`/`running`)
7. [ ] **Cutover de DNS**: nada a fazer aqui de fato — os registros do Cloudflare (T5) já apontam pra VM desde que foram criados; o corte real é desativar o túnel antigo (próximo passo), que é o que estava mascarando o tráfego indo pro destino errado
8. [ ] Apontar o app mobile pro hostname de produção definitivo (`api.oikos.company`), ou confirmar que já aponta (se já foi configurado assim desde o início)
9. [ ] **Desativar o túnel Cloudflare manual** na máquina de desenvolvimento (`cloudflared tunnel run --token ...` — matar o processo/serviço)
10. [ ] Confirmar que uma requisição real do app mobile chega na VM Oracle (não mais na máquina antiga) — checar logs/traces no Grafana (T7)

## Pós-corte (primeiras horas)

- [ ] Monitorar `grafana.oikos.company` continuamente por pelo menos 2h: CPU/RAM da VM, taxa de erro da API, latência
- [ ] Confirmar que o backup automatizado (T8) continua rodando normalmente na nova rotina (próxima execução do timer, ~04:00)
- [ ] Confirmar que a máquina de desenvolvimento não hospeda mais nenhum processo de produção (túnel desligado, stack antiga parada se ainda existia)

## Rollback (se algo der muito errado)

O túnel antigo só deve ser reativado como último recurso — os dados já migrados pra VM Oracle não voltam automaticamente pra origem. Se precisar reverter:

1. Religar o túnel Cloudflare manual na máquina antiga
2. Investigar o problema na VM Oracle com calma, sem pressão de tráfego real
3. Qualquer escrita que aconteceu na VM Oracle durante a janela com tráfego real precisa ser reconciliada manualmente antes de tentar o corte de novo — **não há merge automático entre as duas origens de dados**

## Status

- [ ] Executado — pendente, planejado pra revisão final do épico (ticket `99-review-final.md`), depois de T5/T8/T9 estarem realmente validados na infraestrutura.
