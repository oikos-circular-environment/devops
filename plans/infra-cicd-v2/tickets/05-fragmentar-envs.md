# T05 — Fragmentar as envs por dono

**Status**: não iniciada.
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

- [ ] Conferir `docker compose version` na VM (pré-requisito)
- [ ] Criar Environment `infra-production` e **copiar** (não mover ainda) os secrets de infra de `api-production`
- [ ] Adicionar `CLIENT_API_KEY` e `TURNSTILE_*` ao Environment `web-production`
- [ ] Job de render de `.env.infra` em `deploy-stack.yml`, validado na VM sem ainda plugar no compose
- [ ] Job de render de `.env.web` em `deploy-web.yml`
- [ ] `api-sync` passa a renderizar só `.env.api`
- [ ] `docker-compose.prod.yml` com `env_file` múltiplo; comandos de deploy com os três `--env-file`
- [ ] Validar com `docker compose config` antes do primeiro `up -d`
- [ ] Uma release real de `api` **e** uma de `web` passando pelo caminho novo
- [ ] Só então: apagar `.env.prod` antigo da VM e os secrets órfãos em `api-production`
- [ ] Atualizar `docs/docker-infra.md#2`

## Definição de Pronto

Um deploy de `web` sozinho entrega variável de ambiente nova em produção **sem** nenhuma release do `api`.

## Registro de execução

_(preencher durante a execução)_
