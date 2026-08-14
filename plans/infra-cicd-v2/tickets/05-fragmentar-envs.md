# T05 — Fragmentar as envs por dono

**Status**: **concluída** em 2026-08-14 (falta validar num deploy real, ver [T07](./07-teardown-rebuild.md)).
**Repositório**: `devops`
**Depende de**: [T04](./04-quebrar-deploy-yml.md)

## Escopo

Hoje **só** o job `api-sync` renderiza o `.env.prod` inteiro na VM. Consequência real (web#39/devops#73): uma mudança exclusivamente do `web` só ganhou as variáveis dela quando uma **release do `api`** rodou. Env de um serviço não pode depender do ciclo de deploy de outro.

## Achado que condiciona o desenho

O `--env-file .env.prod` de hoje serve **duas** funções, e as duas precisam ser preservadas:

1. **Interpolação de `${VAR}` no próprio `docker-compose.prod.yml`** — o `api` monta `DATABASE_URL`/`REDIS_URL` assim, e o `web` usa `${CLIENT_API_KEY}`/`${TURNSTILE_*}` mesmo **sem** ter `env_file:` declarado.
2. **Injeção direta no container** via `env_file:` — usada por `postgresql`, `redis`, `minio`, `createbuckets`, `api` e `alloy`.

## Estrutura alvo

Fragmentar por **dono/Environment**, não 1:1 por container:

| Arquivo | Environment | Renderizado por | Conteúdo |
|---|---|---|---|
| `.env.infra` | `infra-production` (novo) | `deploy-stack.yml` | `POSTGRES_*`, `REDIS_PASSWORD`, `MINIO_*`, `PROMETHEUS_REMOTE_WRITE_URL`, `LOKI_URL`, `TEMPO_ENDPOINT` |
| `.env.api` | `api-production` (enxuto) | `deploy-api.yml` | `API_VERSION`, `JWT_SECRET`, `ADMIN_*`, `CLIENT_KEY_MOBILE`, `CLIENT_KEY_WEB`, `CLIENT_KEY_ENFORCE`, `QUORUM_JOB_DELAY_MS`, `ACCOUNT_DELETION_DELAY_MS`, `WORKER_CONCURRENCY`, `PRISMA_QUERY_LOG` |
| `.env.web` | `web-production` | `deploy-web.yml` | `WEB_VERSION`, `CLIENT_API_KEY`, `TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY` |

Em `docker-compose.prod.yml`: `postgresql`/`redis`/`minio`/`createbuckets`/`alloy` passam a `env_file: [.env.infra]`; `api` passa a `env_file: [.env.infra, .env.api]` (precisa do `.env.infra` porque interpola `${POSTGRES_USER}` no `DATABASE_URL` e lê `MINIO_*` direto); `web` continua sem `env_file:`, só dependendo da interpolação.

Todo comando de deploy passa os **três** `--env-file`, inclusive o de `web` — o Compose interpola o arquivo inteiro, não só o serviço alvo do `up -d`.

## Armadilhas

- **`--env-file` múltiplo exige Compose v2.24+.** Conferir `docker compose version` na VM **antes**. Se for anterior, alternativa é concatenar os fragmentos num `.env.prod` combinado no runner antes do `scp` — perde elegância, não depende de feature nova.
- **Segredo duplicado**: `CLIENT_KEY_WEB` (lida pelo `api`) e `CLIENT_API_KEY` (lida pelo `web`) são o **mesmo valor** em Environments diferentes. Rotação exige atualizar os dois em sincronia. Consequência aceita — documentar em `docs/docker-infra.md#2`.
- Passo de maior risco do plano. Manter o `.env.prod` antigo no disco e conferir com `docker compose config` via SSH antes do `up -d` real.

## Ganho colateral

Morre o hack de preservar `WEB_VERSION` durante o render do `api-sync` (`CURRENT_WEB_VERSION=$(ssh ... grep '^WEB_VERSION=' ...)`) — cada pipeline só re-renderiza o próprio fragmento e nunca toca no do outro.

## Checklist

- [x] Conferir `docker compose version` na VM — **v2.40.3**, bem acima do 2.24 exigido
- [x] Environment `infra-production` criado com `POSTGRES_USER/PASSWORD`, `REDIS_PASSWORD`, `MINIO_ACCESS_KEY/SECRET_KEY`
- [x] `CLIENT_API_KEY`, `TURNSTILE_SECRET_KEY` (secrets) e `TURNSTILE_SITE_KEY` (var) adicionados ao `web-production`
- [x] Render de `.env.infra` em `deploy-stack.yml` (`environment: infra-production`)
- [x] Render de `.env.web` em `deploy-web.yml` (job `sync` ganhou `environment: web-production`)
- [x] `sync` do `deploy-api.yml` renderiza só `.env.api`
- [x] `docker-compose.prod.yml` com `env_file` múltiplo; os três `--env-file` em todos os comandos de deploy
- [x] Validado com `docker compose config` local usando os três fragmentos
- [ ] Uma release real de `api` **e** uma de `web` passando pelo caminho novo (depois do rebuild, [T07](./07-teardown-rebuild.md))
- [ ] Só então: apagar `.env.prod` antigo da VM e os secrets órfãos em `api-production`
- [ ] Atualizar `docs/docker-infra.md#2`

## Definição de Pronto

Um deploy de `web` sozinho entrega variável de ambiente nova em produção **sem** nenhuma release do `api`.

## Registro de execução

_(preencher durante a execução)_

## Registro de execução

**2026-08-14** — Implementado. `actionlint` v1.7.7 exit 0 nos 3 workflows; zero referência residual a `.env.prod` em `.github/` e `docker/`.

**Validação por `docker compose config`** (o teste que importa, feito local com fragmentos de exemplo):

- `DATABASE_URL` → `postgresql://oikos:senha-infra@postgresql:5432/oikos` e `REDIS_URL` → `redis://:senha-redis@redis:6379`, montados a partir do `.env.infra`.
- Tags de imagem resolvendo do fragmento certo: `api:v0.3.1` (do `.env.api`) e `web:v0.4.2` (do `.env.web`).
- Serviço `api` recebendo variável dos **dois** arquivos que consome (`JWT_SECRET` do `.env.api`, `MINIO_ACCESS_KEY` do `.env.infra`).
- Serviço `web` recebendo `CLIENT_API_KEY`/`TURNSTILE_*` por interpolação, sem `env_file` próprio, como planejado.
- Única ocorrência de `${` remanescente na saída é o `$${MINIO_ACCESS_KEY}` do `entrypoint` do `createbuckets` — escape intencional, o valor é expandido pelo shell dentro do container.

**Correção não prevista no ticket**: `--env-file` **aborta se o arquivo não existir**, então num rebuild do zero o primeiro `docker compose` falharia — nenhum dos três fragmentos existe numa VM nova. A composite action `sync-deploy-files` e o step de sync do `deploy-stack.yml` passaram a fazer `touch` dos três arquivos junto do `mkdir -p`, de forma idempotente. Sem isso o [T07](./07-teardown-rebuild.md) quebraria no primeiro deploy.

**`.gitignore`**: passou a ignorar `docker/.env.{infra,api,web}` — antes só `docker/.env.prod` estava coberto, e um render local de teste entraria no commit.

**Pendente de propósito**: os secrets duplicados em `api-production` (`POSTGRES_*`, `REDIS_PASSWORD`, `MINIO_*`, `CLIENT_API_KEY`, `TURNSTILE_*`) **não** foram removidos ainda. Só saem depois de uma release real de `api` e de `web` passar pelo caminho novo — remover antes deixaria o pipeline antigo sem rede de segurança se precisar reverter.
