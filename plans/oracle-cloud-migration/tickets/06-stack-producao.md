# T6 — `devops`: Stack de Produção

**Status**: Escrito e validado localmente (builds passam, web testado servindo HTTP 200) — falta só testar na VM real (depende de T4)
**Repositório**: `oikos-circular-environment/devops`

## Escopo

Os arquivos que definem o que roda na `A1.Flex`: Dockerfiles, `docker-compose.prod.yml` e `nginx.conf`. Limite de memória explícito em todo serviço — nenhum container fica livre pra consumir o resto da VM.

## Fora de escopo

Pipeline de deploy que usa esses arquivos (T9); observabilidade (T7, roda na outra VM).

## Referências de spec

- `04-tech-plan.md` §Abordagem Arquitetural (tabela de orçamento de memória), §Arquitetura de Componentes (`oikos/devops`)
- `docs/infra-monitoring-producao.md` (origem dos valores de memória herdados)

## Dependências

T4 (precisa da VM pra testar de verdade, mesmo que os arquivos possam ser escritos em paralelo).

## Checklist

- [x] `docker/Dockerfile.api.prod` — migrado do `api`, `CMD` simplificado pra `node --import ./dist/lib/otel.js dist/server.js` (migration sai do `CMD`, vira passo do deploy em T9) — build local validado
- [x] `docker/Dockerfile.web.prod` — build standalone multi-stage — build local validado, container testado servindo HTTP 200
- [x] `docker/init-db.sh` — migrado do `api` (extensão postgis)
- [x] `docker/docker-compose.prod.yml` — serviço `postgresql`, limite 512MB
- [x] `docker/docker-compose.prod.yml` — serviço `redis`, limite 128MB, `REDIS_AOF_ENABLED=yes` (persistência, necessário pro backup em T8)
- [x] `docker/docker-compose.prod.yml` — serviço `minio`, limite 256MB
- [x] `docker/docker-compose.prod.yml` — serviço `createbuckets` (idempotente, cria bucket `oikos` com policy pública)
- [x] `docker/docker-compose.prod.yml` — serviço `api`, limite 512MB, `image:` (GHCR) + `build:` (context `../../api`, pra validar localmente)
- [x] `docker/docker-compose.prod.yml` — serviço `web`, limite 512MB, `NODE_OPTIONS="--max-old-space-size=384"`
- [x] `docker/docker-compose.prod.yml` — serviço `nginx`, limite 64MB
- [x] `docker/docker-compose.prod.yml` — serviços `cadvisor` (128MB), `node-exporter` (64MB), `alloy` (128MB) — ver T7
- [x] `docker/docker-compose.prod.yml` — nome do compose project mantido como `oikos-prod` (dashboards do T7 dependem disso)
- [x] `docker/.env.prod.example` — criado, cobre todas as vars novas (versões de imagem, endpoints de observabilidade)
- [x] `.gitignore` do `devops` atualizado: `docker/.env.prod`, `docker/certs/`, `docker/logs/` nunca commitados
- [x] `nginx/nginx.conf` — roteia `api.oikos.company` → `api:3333`
- [x] `nginx/nginx.conf` — roteia `oikos.company` → `web:3000`
- [x] `nginx/nginx.conf` — roteia `grafana.oikos.company` → placeholder `__OBS_VM_PRIVATE_IP__` (substituído via `sed` no deploy, não envsubst do nginx — evita colidir com `$host`/`$remote_addr` nativos)
- [x] `nginx/nginx.conf` — roteia `minio.oikos.company` → console do MinIO (porta 9001); porta 9000 (API S3) **não** exposta via nginx
- [x] `nginx/nginx.conf` — TLS com certificado Cloudflare Origin CA (arquivo, de T5 — path `/etc/nginx/certs/`)
- [x] `docker/systemd/oikos-web-restart.{service,timer}` — restart noturno (03:00) do `web` (mitigação do memory leak conhecido do Next.js — [vercel/next.js#88603](https://github.com/vercel/next.js/discussions/88603)). **Assume** que o deploy coloca os arquivos do `devops` em `/opt/oikos/` na VM — confirmar esse path quando T9/T4 definirem o layout real
- [x] Build validado localmente (arquitetura nativa, não arm64 ainda): `docker build` de `api` e `web` passam; `web` testado rodando e respondendo HTTP 200
- [ ] Build arm64 (via Buildx+QEMU) — pendente, fica pro T9 (CI já roda em arm64 nativamente via matriz/QEMU) ou validação manual quando a VM existir

## Definição de Pronto

`docker compose -f docker-compose.prod.yml up -d` sobe todos os serviços saudáveis na `A1.Flex`, `nginx` responde nos 4 hostnames roteando pro serviço certo, e nenhum container ultrapassa seu limite de memória sob uso normal.

## Nota

Builds validados nesta sessão só na arquitetura nativa do host de desenvolvimento — confirma a lógica dos Dockerfiles (deps, prisma generate, tsc build, standalone do Next.js), mas não substitui testar o build arm64 real contra a VM Oracle.
