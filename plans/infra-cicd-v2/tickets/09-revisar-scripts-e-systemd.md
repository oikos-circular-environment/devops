# T09 — Revisar o que sobrou em `scripts/` e `docker/systemd/`

**Status**: não iniciada. Levantamento feito em 2026-08-14, decisão adiada a pedido do usuário.
**Repositório**: `devops`

## Escopo

Decidir, item a item, o que continua útil em `scripts/` e `docker/systemd/` e remover o que não estiver sendo usado. O rebuild do zero mostrou que sobrou coisa nesses diretórios cuja utilidade ninguém confirmou — e coisa que "existia" mas não estava no ar.

Não é limpeza cosmética: cada arquivo aqui é algo que alguém vai assumir que funciona.

## Inventário (verificado em 2026-08-14)

### `docker/systemd/`

| Arquivo | Situação |
|---|---|
| `oikos-web-restart.service` | Instalado e **habilitado** na VM nova. `Type=oneshot`, roda `docker compose ... restart web` |
| `oikos-web-restart.timer` | `enabled`, próxima execução 03:00 UTC |

Confirmado na `A1.Flex` (`systemctl list-unit-files 'oikos*'`): as duas units estão registradas em `/etc/systemd/system`, instaladas pelo `scripts/reconcile-systemd.sh` durante o `deploy-infra`. **Está sendo aplicado, sim** — diferente do que acontecia antes do [T06](./06-provisionamento-declarativo.md), quando os arquivos eram copiados para `/opt/oikos/docker/systemd/` e nunca registrados.

**A dúvida real é se ainda faz sentido.** O restart noturno foi criado como mitigação de um vazamento de memória do Next.js (`vercel/next.js#88603`), documentado em `plans/oracle-cloud-migration/04-tech-plan.md` e entregue no ticket 06 daquele plano. Pontos a checar antes de decidir:

- O `web` hoje roda **Next.js 16.3.0** (`web/package.json`); a discussão citada é de versões próximas da 16.2.9. Verificar se o vazamento persiste na versão atual.
- Já existe o teto `NODE_OPTIONS="--max-old-space-size=384"` (`docker/docker-compose.prod.yml:141`) contra um limite de container de 512M. O restart é mitigação **adicional**; se o teto soziber segurar, o timer é redundante.
- Se o vazamento não for mais reproduzível, o timer deixa de ser proteção e vira um restart diário sem motivo — que derruba a sessão de quem estiver usando às 03:00.
- Alternativa mais honesta que o restart cego: alerta no Alertmanager sobre crescimento de memória do container `web`, com a stack de observabilidade que já existe. Trata a causa em vez de esconder o sintoma.

**Atenção imediata**: o timer dispara às 03:00 UTC e roda `docker compose restart web`. Enquanto os deploys não subirem, não existe container `web` — a unit vai falhar em silêncio. Inofensivo, mas gera ruído no journal.

### `scripts/`

| Arquivo | Quem usa | Situação |
|---|---|---|
| `reconcile-systemd.sh` | `.github/actions/sync-deploy-files` | **Em uso.** Criado no T06: instala em `/etc/systemd/system` o que está em `docker/systemd/` e **remove** unit `oikos-*` que não exista mais no repo. Se as units de restart forem removidas, este script é o que garante que elas saiam da VM também |
| `migrate-data.sh` | só citado em `docs/docker-infra.md` | **Revisar.** Migração one-time de Postgres + MinIO da máquina de desenvolvimento para a VM Oracle, feita no cutover (ticket 10 do `oracle-cloud-migration`). O cutover já aconteceu e a infra foi reconstruída duas vezes desde então. Provavelmente é código morto — confirmar se há algum cenário futuro que o justifique antes de apagar |

## Contexto que motivou o ticket

Ao longo do rebuild do zero, seis coisas se revelaram passos manuais que nunca estiveram no código: OCI CLI, units systemd, `/opt/oikos`, `.env.observability`, `observability/prometheus/prometheus.yml` e o `docker login` no GHCR. O padrão comum é o mesmo: **arquivo existir no repo não significa estar no ar, e estar no ar não significa ser necessário.**

Este ticket fecha a ponta oposta da mesma questão — o que está no repo e talvez não devesse estar.

## Checklist

- [ ] Verificar se o vazamento de memória do Next.js ainda se reproduz na 16.3.0
- [ ] Decidir o destino do `oikos-web-restart.{service,timer}`: manter, substituir por alerta de memória no Alertmanager, ou remover
- [ ] Decidir o destino do `scripts/migrate-data.sh`
- [ ] Se algo for removido, confirmar que o `reconcile-systemd.sh` tirou a unit da VM (é o que ele existe para fazer)
- [ ] Atualizar `docs/docker-infra.md` e o ticket 06 do `oracle-cloud-migration` conforme a decisão

## Definição de Pronto

Todo arquivo em `scripts/` e `docker/systemd/` tem uso confirmado e documentado, ou foi removido do repo e da VM.

## Registro de execução

_(preencher durante a execução)_
