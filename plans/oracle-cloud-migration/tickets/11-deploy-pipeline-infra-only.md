# T11 — `devops`: Deploy pipeline — desacoplar infra de release do app

**Status**: Planejamento — ainda não implementada. Motivada por um bug real de 2026-07-03: `www.oikos.company` caía na API porque faltava `server_name` no `nginx.conf` (corrigido em T5/T6), mas a correção ficou sem nenhum caminho de deploy — precisou de um `workflow_dispatch` forçado em `web` sem motivo real de rebuild, e mesmo assim o nginx não recarrega sozinho.
**Repositório**: `oikos-circular-environment/devops`

## Escopo

- Separar o job atual de `api-production`/`web-production` em duas responsabilidades via `needs:`:
  - **build**: só roda com `repository_dispatch` (de `api`/`web`) ou `workflow_dispatch` explícito — builda a imagem, publica no GHCR.
  - **sync+deploy**: sincroniza `nginx/`, `observability/`, `scripts/`, `docker-compose.prod.yml` pra VM, roda `pull`/`up -d` dos serviços e recarrega o nginx.
- Novo trigger `push` em `production` do próprio `devops` (path-filter em `nginx/**`, `observability/**`, `scripts/**`) que dispara só o job de sync+deploy — sem build, reaproveitando `API_VERSION`/`WEB_VERSION` já existentes no `.env.prod` remoto (lidos antes de qualquer sync, nunca sobrescritos às cegas — mesmo padrão que o job `web-production` já usa hoje pra preservar `WEB_VERSION`).
- Step fixo de reload do nginx (`docker compose exec nginx nginx -s reload`) em **toda** execução de deploy — tanto no fluxo normal (build → sync+deploy) quanto no novo fluxo disparado por push do `devops`. Fecha o gap de hoje: o `nginx.conf` é copiado pra VM via `scp`, mas nada reinicia/recarrega o container, então a config nova fica sem efeito até alguém rodar isso manualmente.
- Fluxo disparado por push do `devops` roda pros dois serviços (`api` e `web`), já que uma mudança de infra (ex: `nginx.conf`) pode afetar o roteamento dos dois.

## Fora de escopo

- Mudar o mecanismo de trigger do `api`/`web` (`repository_dispatch` continua igual).
- Adotar tag `:latest` no GHCR — decisão consciente de manter o `.env.prod` remoto (`API_VERSION`/`WEB_VERSION`) como fonte de verdade de qual versão está rodando, em vez de uma tag móvel que poderia divergir do que foi realmente promovido (discutido e decidido em 2026-07-03).
- Modularizar o job de build inteiro em `build → sync → backup → migrate → deploy-container` totalmente encadeado (item já listado como melhoria futura separada em T9) — esse ticket só separa build de sync+deploy, não vai além disso.

## Decisões

- **Fonte de verdade de versão para o fluxo disparado por push no `devops`**: ler `API_VERSION`/`WEB_VERSION` do `.env.prod` já presente na VM, nunca pressupor `:latest` do GHCR (decisão de 2026-07-03, ver discussão na sessão — evita bump de versão não intencional junto de um fix que é só de infra).

## Em aberto (decidir antes ou durante a implementação)

- [ ] O path-filter do trigger `push` inclui `docker-compose.prod.yml` inteiro (risco: um push que mexa nesse arquivo por outro motivo, não relacionado a nginx/observability, dispara esse job à toa) ou fica restrito só a `nginx/**` + `observability/**` + `scripts/**`, tratando mudança em `docker-compose.prod.yml` caso a caso?
- [ ] `nginx -s reload` basta (não recarrega imagem/env do próprio serviço nginx) ou em algum caso precisa de `up -d --force-recreate nginx`?

## Referências de spec

- `tickets/09-deploy-pipeline.md` §Melhorias futuras (job atual, gaps já documentados)
- `04-tech-plan.md` §`oikos/devops` (linha do `.github/workflows/deploy.yml`)

## Dependências

T9 (é o job existente que será refatorado).

## Checklist

- [ ] Separar `api-production`/`web-production` em jobs `build` + `sync-deploy` (via `needs:`), preservando o comportamento atual pro fluxo normal
- [ ] Novo trigger `push` (branch `production`, path-filter conforme decisão acima) rodando só `sync-deploy`
- [ ] Step de leitura de `API_VERSION`/`WEB_VERSION` do `.env.prod` remoto antes de decidir o que sincronizar, quando não vem de um build novo
- [ ] Step fixo de reload do nginx em toda execução (fluxo normal e fluxo por push)
- [ ] Fluxo por push do `devops` cobre `api` e `web` juntos (não targeted como hoje)
- [ ] Validar de ponta a ponta: um commit alterando só `nginx/nginx.conf` mergeado em `production` dispara o `deploy.yml` sozinho, sincroniza e recarrega o nginx, sem rebuildar nem trocar versão de `api`/`web`

## Definição de Pronto

Um commit alterando só `nginx/nginx.conf` (ou `observability/`) mergeado em `production` dispara o `deploy.yml` sozinho, sincroniza e recarrega o nginx, sem rebuildar nem trocar a versão de `api`/`web` — validado repetindo o cenário real de hoje (fix do `www.oikos.company`).
