# T11 — `devops`: Deploy pipeline — desacoplar infra de release do app

**Status**: Implementada, aguardando validação real (merge + push em `production` ainda não testado de ponta a ponta). Motivada por um bug real de 2026-07-03: `www.oikos.company` caía na API porque faltava `server_name` no `nginx.conf` (corrigido em T5/T6), mas a correção ficou sem nenhum caminho de deploy — precisou de um `workflow_dispatch` forçado em `web` sem motivo real de rebuild, e mesmo assim o nginx não recarregava sozinho.
**Repositório**: `oikos-circular-environment/devops`

## Escopo

- Novo job independente `infra-production` em `deploy.yml`, disparado só pelo trigger `push` (branch `production`, path-filter em `nginx/**`, `observability/**`, `scripts/**`, `docker/docker-compose.prod.yml`) — sincroniza esses arquivos pra VM e recarrega os serviços afetados. Não builda nem redeploya `api`/`web`, não toca no `.env.prod`.
- Implementação real ficou **mais simples** que o desenho original discutido na sessão (jobs `build`/`sync-deploy` ligados por `needs:`, com leitura de `API_VERSION`/`WEB_VERSION` do `.env.prod` remoto): como o `infra-production` não builda nem faz `pull`/`up -d` de `api`/`web`, ele não precisa saber a versão de nada — só mexe nos arquivos que `nginx` e `alloy` leem em runtime. Isso também evitou o job novo precisar de qualquer secret do Environment `api-production`/`web-production` (`SSH_DEPLOY_KEY`/`VM_HOST` são secret/variable de repositório, acessíveis sem Environment — ver `docs/terraform-cloud-credentials-setup.md` §9.1).
- Step de reload adicionado nos **três** jobs (`api-production`, `web-production`, `infra-production`): `docker compose exec nginx nginx -s reload` (sem downtime) + `docker compose restart alloy` (não expõe sinal de reload). Fecha o gap onde `nginx.conf`/`alloy-prod.alloy` eram copiados pra VM via `scp` mas nunca recarregados.
- `cadvisor`/`node-exporter` não recebem restart — não montam nenhum arquivo de `nginx/` ou `observability/` (confirmado lendo `docker-compose.prod.yml`), só `nginx` (`nginx.conf`) e `alloy` (`alloy-prod.alloy`) dependem desses diretórios.
- `concurrency.group` mudou de `deploy-${{ action/service }}` (um grupo por serviço) pra um grupo único `deploy-vm` — os três jobs mexem nos mesmos arquivos/containers na mesma VM via SSH, precisam ser serializados entre si, não só contra reexecuções de si mesmos.

## Fora de escopo

- Mudar o mecanismo de trigger do `api`/`web` (`repository_dispatch` continua igual).
- Adotar tag `:latest` no GHCR — decisão consciente de manter o `.env.prod` remoto (`API_VERSION`/`WEB_VERSION`) como fonte de verdade de qual versão está rodando (discutido e decidido em 2026-07-03). Ficou ainda mais irrelevante pra esse ticket específico, já que o novo job nem mexe em versão de `api`/`web`.
- Modularizar o job de build inteiro em `build → sync → backup → migrate → deploy-container` totalmente encadeado (item já listado como melhoria futura separada em T9) — não foi necessário pra resolver o caso concreto (infra-only), fica pra depois se algum dia for preciso.

## Decisões

- **Path-filter do `push` inclui `docker/docker-compose.prod.yml` inteiro** (não só `nginx/**`+`observability/**`+`scripts/**`) — aceito o risco de disparar o job à toa numa mudança nesse arquivo não relacionada a infra (ex: limite de memória de um serviço), porque o custo de rodar esse job à toa é baixo (só sincroniza arquivo + reload, não builda nada).
- **`nginx -s reload` + `restart alloy`, sem `--force-recreate`** — cobre o caso de mudança só de config (bind mount), que é o único cenário que esse trigger cobre hoje. Se um dia o próprio serviço `nginx`/`alloy` mudar no compose (imagem, variável de ambiente), aí sim precisaria de `up -d` — não implementado agora porque não é o caso de uso motivador.

## Referências de spec

- `tickets/09-deploy-pipeline.md` §Melhorias futuras (job atual, gaps já documentados)
- `04-tech-plan.md` §`oikos/devops` (linha do `.github/workflows/deploy.yml`)
- `.github/workflows/deploy.yml` (job `infra-production`)

## Dependências

T9 (job existente onde os steps de reload também foram adicionados).

## Checklist

- [x] Novo job `infra-production`, disparado só por `push` em `production` (path-filter conforme decisão acima)
- [x] Step de sync (scp) de `nginx/`, `observability/`, `scripts/`, `docker/docker-compose.prod.yml` no job novo, sem tocar em `.env.prod`
- [x] Step de reload do nginx + restart do alloy no job novo
- [x] Mesmo step de reload adicionado em `api-production` e `web-production` (gap valia pros três caminhos, não só pro novo)
- [x] `concurrency.group` único (`deploy-vm`) serializando os três jobs
- [ ] Validar de ponta a ponta: um commit alterando só `nginx/nginx.conf` mergeado em `production` dispara o `infra-production` sozinho, sincroniza e recarrega o nginx, sem rebuildar nem trocar versão de `api`/`web` — pendente até esse PR ser mergeado pelo usuário e o push real acontecer

## Definição de Pronto

Um commit alterando só `nginx/nginx.conf` (ou `observability/`) mergeado em `production` dispara o `deploy.yml` (job `infra-production`) sozinho, sincroniza e recarrega o nginx, sem rebuildar nem trocar a versão de `api`/`web` — falta validar repetindo o cenário real de hoje (fix do `www.oikos.company`, ainda pendente de deploy efetivo).
