# T6 — `devops`: Stack de Produção

**Status**: **Pronta.** Stack completa rodando de verdade na `A1.Flex` (bootstrap manual via SSH), validada de ponta a ponta pela internet real (`https://api.oikos.company/health`, `oikos.company`, `minio.oikos.company` respondendo via Cloudflare). `grafana.oikos.company` retorna 502 — esperado, a stack de observabilidade (T7) ainda não foi implantada na `E2.1.Micro`.
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

## Bugs encontrados e corrigidos no bootstrap real (2026-07-03)

Nenhum destes aparecia nos testes locais — só surgiram testando contra a VM de verdade:

1. **`docker compose` nunca lia `.env.prod`** — Compose só carrega `.env` automaticamente; toda invocação (em `deploy.yml` e nos runbooks) precisava de `--env-file .env.prod` explícito. Sem isso, `${API_VERSION}`, `${POSTGRES_USER}` etc. resolviam em branco/`latest`. Corrigido em `deploy.yml` e toda a documentação que roda `docker compose` contra `docker-compose.prod.yml`.
2. **`nginx.conf` referenciava `cloudflare-origin.pem`/`.key`**, mas `deploy.yml` materializa `origin.pem`/`origin.key` — nginx falhava ao subir (certificado não encontrado).
3. **Placeholder `__OBS_VM_PRIVATE_IP__` nunca era substituído** — `deploy.yml` nunca tinha o passo de `sed` que o próprio comentário do `nginx.conf` dizia que deveria existir. Corrigido manualmente na VM nesta sessão, e automatizado em `deploy.yml` (ver T9, nota 7).
4. **Healthcheck da `api` usava `http://localhost:3333/health`** — dentro do container Alpine, `localhost` resolve pra `::1` (IPv6) primeiro, e o Fastify só escuta em IPv4 (`0.0.0.0`), causando falso-negativo permanente de "connection refused". Corrigido pra `127.0.0.1` explícito.
5. **`observability/` nunca fazia parte do `scp` de sincronização** — `deploy.yml` só copiava `docker`, `nginx`, `scripts`, mas o volume do `alloy` referencia `../observability/alloy/alloy-prod.alloy`. Sem esse diretório, o Docker cria automaticamente um diretório vazio no lugar do arquivo esperado, e o container do `alloy` falha ao montar. Corrigido em `deploy.yml` (ver T9, nota 6).

## Checklist

- [x] `docker/Dockerfile.api.prod` — build `arm64` real via Buildx+QEMU, testado rodando na `A1.Flex`
- [x] `docker/Dockerfile.web.prod` — build `arm64` real via Buildx+QEMU, testado rodando na `A1.Flex`
- [x] `docker/init-db.sh` — migrado do `api` (extensão postgis), migration `prisma migrate deploy` rodou de verdade contra Postgres real
- [x] `docker/docker-compose.prod.yml` — serviço `postgresql`, limite 512MB — confirmado aplicado de verdade (`docker inspect`)
- [x] `docker/docker-compose.prod.yml` — serviço `redis`, limite 128MB, `REDIS_AOF_ENABLED=yes` (persistência, necessário pro backup em T8)
- [x] `docker/docker-compose.prod.yml` — serviço `minio`, limite 256MB
- [x] `docker/docker-compose.prod.yml` — serviço `createbuckets` (idempotente, cria bucket `oikos` com policy pública) — rodou e saiu com exit 0
- [x] `docker/docker-compose.prod.yml` — serviço `api`, limite 512MB — rodando `healthy`, uso real ~109MB
- [x] `docker/docker-compose.prod.yml` — serviço `web`, limite 512MB — rodando, uso real ~32MB
- [x] `docker/docker-compose.prod.yml` — serviço `nginx`, limite 64MB — rodando, roteando os 4 hostnames
- [x] `docker/docker-compose.prod.yml` — serviços `cadvisor` (128MB), `node-exporter` (64MB), `alloy` (128MB) — todos `healthy`/`running`
- [x] `docker/docker-compose.prod.yml` — nome do compose project mantido como `oikos-prod` (dashboards do T7 dependem disso)
- [x] `docker/.env.prod.example` — criado, cobre todas as vars novas (versões de imagem, endpoints de observabilidade)
- [x] `.gitignore` do `devops` atualizado: `docker/.env.prod`, `docker/certs/` nunca commitados
- [x] `nginx/nginx.conf` — roteia `api.oikos.company` → `api:3333` — testado via `https://api.oikos.company/health` real
- [x] `nginx/nginx.conf` — roteia `oikos.company` → `web:3000` — testado via `https://oikos.company` real (200)
- [x] `nginx/nginx.conf` — roteia `grafana.oikos.company` → IP privado da `E2.1.Micro` — roteamento correto, 502 porque T7 ainda não rodou
- [x] `nginx/nginx.conf` — roteia `minio.oikos.company` → console do MinIO (porta 9001); porta 9000 (API S3) **não** exposta via nginx — testado via `https://minio.oikos.company` real (200)
- [x] `nginx/nginx.conf` — TLS com certificado Cloudflare Origin CA — testado via HTTPS real (HTTP/2, TLS ok)
- [x] `docker/systemd/oikos-web-restart.{service,timer}` — restart noturno (03:00) do `web` (mitigação do memory leak conhecido do Next.js — [vercel/next.js#88603](https://github.com/vercel/next.js/discussions/88603))
- [x] `api` loga via OTLP (`pino-opentelemetry-transport`), sem volume de logs
- [x] Build `arm64` real via Buildx+QEMU — imagens publicadas em `ghcr.io/oikos-circular-environment/{api,web}:bootstrap` (tag temporária desta validação; T9 vai gerar tags SemVer reais)

## Definição de Pronto

`docker compose --env-file .env.prod -f docker-compose.prod.yml up -d` sobe todos os serviços saudáveis na `A1.Flex`, `nginx` responde nos 4 hostnames roteando pro serviço certo, e nenhum container ultrapassa seu limite de memória sob uso normal. **Confirmado de verdade em 2026-07-03.**
