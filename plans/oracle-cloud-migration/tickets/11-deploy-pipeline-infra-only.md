# T11 — `devops`: Deploy pipeline — desacoplar infra de release do app

**Status**: **Pronta.** Validada de ponta a ponta: merge até `production` tocando só `nginx/` disparou `infra-production` sozinho (sem acionar `api-production`/`web-production`), o `--force-recreate` recriou `nginx`/`alloy` de verdade, e `https://www.oikos.company/` + `https://oikos.company/` confirmados via internet real servindo o Next.js (`200`, `x-powered-by: Next.js`, corpo idêntico entre os dois — `api.oikos.company` responde `application/json`, confirmando que não é mais a API). Motivada por um bug real de 2026-07-03: `www.oikos.company` caía na API porque faltava `server_name` no `nginx.conf` (corrigido em T5/T6), mas a correção ficou sem nenhum caminho de deploy — precisou de um `workflow_dispatch` forçado em `web` sem motivo real de rebuild, e mesmo assim o nginx não recarregava sozinho.

### Achado em produção (2026-07-03): reload/restart não atualiza bind mount de arquivo único

O primeiro run real do `infra-production` (disparado por um merge em `production` tocando só `nginx.conf`) sincronizou o arquivo certinho (`sed` resolveu `OBSERVABILITY_PRIVATE_IP` corretamente), mas o `nginx -s reload` falhou: `host not found in upstream "__OBS_VM_PRIVATE_IP__"` — como se o arquivo nunca tivesse sido alterado. Causa: `nginx.conf`/`alloy-prod.alloy` são montados no `docker-compose.prod.yml` como bind mount de **arquivo único** (não diretório). `sed -i` reescreve via arquivo temporário + rename, trocando o inode no host — mas o bind mount de arquivo único do Docker fica preso no inode que existia no momento em que o container foi criado. Nem `nginx -s reload` (só re-lê o que o mount já resolve) nem `docker compose restart` (só reinicia o processo, não recria o container) resolvem isso — só recriar o container remonta o bind no inode novo.

**Implicação séria**: como o container do `nginx` nunca tinha sido recriado desde o bootstrap manual (T6) — `deploy.yml` sempre fez só `up -d api`/`up -d web`, nunca mexeu no `nginx` — é provável que o fix do `www.oikos.company` (T5/T6) **nunca tenha realmente pego em produção**, mesmo depois de mergeado, porque o container seguiu servindo uma versão congelada do arquivo. Corrigido trocando o step de reload/restart por `docker compose up -d --force-recreate --no-deps nginx alloy` nos três jobs — recria os dois containers (bind remonta no inode atual), sem rebuildar imagem nem afetar `api`/`web` (`--no-deps`).
**Repositório**: `oikos-circular-environment/devops`

## Escopo

- Novo job independente `infra-production` em `deploy.yml`, disparado só pelo trigger `push` (branch `production`, path-filter em `nginx/**`, `observability/**`, `scripts/**`, `docker/docker-compose.prod.yml`) — sincroniza esses arquivos pra VM e recarrega os serviços afetados. Não builda nem redeploya `api`/`web`, não toca no `.env.prod`.
- Implementação real ficou **mais simples** que o desenho original discutido na sessão (jobs `build`/`sync-deploy` ligados por `needs:`, com leitura de `API_VERSION`/`WEB_VERSION` do `.env.prod` remoto): como o `infra-production` não builda nem faz `pull`/`up -d` de `api`/`web`, ele não precisa saber a versão de nada — só mexe nos arquivos que `nginx` e `alloy` leem em runtime. Isso também evitou o job novo precisar de qualquer secret do Environment `api-production`/`web-production` (`SSH_DEPLOY_KEY`/`VM_HOST` são secret/variable de repositório, acessíveis sem Environment — ver `docs/terraform-cloud-credentials-setup.md` §9.1).
- Step adicionado nos **três** jobs (`api-production`, `web-production`, `infra-production`): `docker compose up -d --force-recreate --no-deps nginx alloy`. Fecha o gap onde `nginx.conf`/`alloy-prod.alloy` eram copiados pra VM via `scp` mas nunca chegavam a ser aplicados de verdade (ver achado acima — a primeira tentativa usou `reload`/`restart`, que não resolve por causa do bind mount de arquivo único).
- `cadvisor`/`node-exporter` não recebem restart — não montam nenhum arquivo de `nginx/` ou `observability/` (confirmado lendo `docker-compose.prod.yml`), só `nginx` (`nginx.conf`) e `alloy` (`alloy-prod.alloy`) dependem desses diretórios.
- `concurrency.group` mudou de `deploy-${{ action/service }}` (um grupo por serviço) pra um grupo único `deploy-vm` — os três jobs mexem nos mesmos arquivos/containers na mesma VM via SSH, precisam ser serializados entre si, não só contra reexecuções de si mesmos.

## Fora de escopo

- Mudar o mecanismo de trigger do `api`/`web` (`repository_dispatch` continua igual).
- Adotar tag `:latest` no GHCR — decisão consciente de manter o `.env.prod` remoto (`API_VERSION`/`WEB_VERSION`) como fonte de verdade de qual versão está rodando (discutido e decidido em 2026-07-03). Ficou ainda mais irrelevante pra esse ticket específico, já que o novo job nem mexe em versão de `api`/`web`.
- Modularizar o job de build inteiro em `build → sync → backup → migrate → deploy-container` totalmente encadeado (item já listado como melhoria futura separada em T9) — não foi necessário pra resolver o caso concreto (infra-only), fica pra depois se algum dia for preciso.

## Decisões

- **Path-filter do `push` inclui `docker/docker-compose.prod.yml` inteiro** (não só `nginx/**`+`observability/**`+`scripts/**`) — aceito o risco de disparar o job à toa numa mudança nesse arquivo não relacionada a infra (ex: limite de memória de um serviço), porque o custo de rodar esse job à toa é baixo (só sincroniza arquivo + reload, não builda nada).
- **`up -d --force-recreate --no-deps`, não `reload`/`restart`** — única forma confirmada de fazer o bind mount de arquivo único (`nginx.conf`, `alloy-prod.alloy`) refletir mudança de conteúdo (ver achado em produção acima). `--no-deps` evita recriar `api`/`web` (dependências do `nginx` no compose) sem necessidade.

## Referências de spec

- `tickets/09-deploy-pipeline.md` §Melhorias futuras (job atual, gaps já documentados)
- `04-tech-plan.md` §`oikos/devops` (linha do `.github/workflows/deploy.yml`)
- `.github/workflows/deploy.yml` (job `infra-production`)

## Dependências

T9 (job existente onde os steps de reload também foram adicionados).

## Checklist

- [x] Novo job `infra-production`, disparado só por `push` em `production` (path-filter conforme decisão acima)
- [x] Step de sync (scp) de `nginx/`, `observability/`, `scripts/`, `docker/docker-compose.prod.yml` no job novo, sem tocar em `.env.prod`
- [x] Trigger `push` → `infra-production` confirmado disparando de verdade em produção (run real, sem acionar `api-production`/`web-production`)
- [x] Achado e corrigido: reload/restart não atualiza bind mount de arquivo único — trocado por `up -d --force-recreate --no-deps nginx alloy` nos três jobs
- [x] `concurrency.group` único (`deploy-vm`) serializando os três jobs
- [x] Validado de ponta a ponta: push em `production` recriou `nginx`/`alloy` de verdade, `www.oikos.company`/`oikos.company` confirmados servindo o Next.js via internet real (2026-07-03)

## Definição de Pronto

Confirmado: um commit alterando só `nginx/nginx.conf` mergeado em `production` disparou o `deploy.yml` (job `infra-production`) sozinho, recriou nginx/alloy sem rebuildar nem trocar versão de `api`/`web`, e `www.oikos.company`/`oikos.company` responderam certo via internet real.
