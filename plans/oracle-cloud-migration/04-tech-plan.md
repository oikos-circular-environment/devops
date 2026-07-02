# Migração de Produção para Oracle Cloud — Tech Plan

## Abordagem Arquitetural

**Topologia**: duas VMs na mesma VCN Oracle, subnet privada compartilhada (comunicação por IP privado 10.x.x.x, não consome egress nem exige portas públicas extras).
- `A1.Flex` (2 OCPU/12GB): `postgresql`, `redis`, `minio`, `createbuckets`, `api`, `web`, `nginx`, e a camada de coleta de observabilidade (Alloy no lugar do otelcol, cAdvisor, node-exporter) — tudo via `docker-compose.prod.yml` único.
- `E2.1.Micro` (1GB): `prometheus`, `loki`, `tempo`, `grafana`, `alertmanager` via `docker-compose.observability.yml`. Sem nenhuma porta pública — só alcançável pela `A1.Flex` via IP privado.

**Orçamento de memória — `A1.Flex`** (limites explícitos em todo serviço, nenhum container fica livre pra consumir o resto da VM; valores herdados de `docs/infra-monitoring-producao.md`, calibrados originalmente pra EC2 2GB e mantidos por disciplina mesmo com 12GB disponíveis):

| Serviço | Limite | Observação |
|---|---|---|
| `postgresql` | 512MB | — |
| `redis` | 128MB | — |
| `minio` | 256MB | — |
| `api` | 512MB | — |
| `web` | 512MB | `NODE_OPTIONS="--max-old-space-size=384"` — trava o heap do V8 numa fração do limite, deixando ~128MB pra memória não-heap. Necessário porque há relatos não resolvidos de memory leak gradual em produção Docker/Kubernetes em versões próximas da 16.2.9 ([vercel/next.js#88603](https://github.com/vercel/next.js/discussions/88603)) — sem esse teto, o processo cresceria até o container ser morto por OOM. Mitigação adicional: **restart agendado noturno** (`docker compose restart web` via cron, mesmo mecanismo do backup) pra resetar qualquer crescimento lento antes de ameaçar o limite |
| `nginx` | 64MB | — |
| `cadvisor` | 128MB | métricas por container |
| `node-exporter` | 64MB | métricas de host |
| `alloy` | 128MB | substitui otelcol — recebe traces/métricas/**logs** via OTLP direto da `api` (`pino-opentelemetry-transport`, sem arquivo/tail), + scrape de cadvisor/node-exporter |
| **Total** | **~2,3GB** | de 12GB disponíveis na VM — folga grande pra crescimento |

**Observabilidade de host + container**: `cAdvisor` expõe métrica por container (CPU, RAM, rede, disco, lendo do socket do Docker) e `node-exporter` expõe métrica de host (CPU total, RAM disponível, disco) — ambos só na `A1.Flex`. `Alloy` faz scrape dos dois e `remote_write`/`push` pro Prometheus/Loki na `E2.1.Micro` via IP privado. Reaproveita os 2 dashboards Grafana já desenhados em `docs/infra-monitoring-producao.md` ("Infra Overview" — CPU/RAM/disco do host + por container; "Container Detail" — dropdown por serviço com throttling de CPU, working set vs. cache, restart count) — só adaptar o filtro de `container_label_com_docker_compose_project` pro nome do novo `docker-compose.prod.yml` (manter `oikos-prod` por continuidade).

**Exposição pública**: só a `A1.Flex` recebe tráfego externo, só na porta 443. `nginx` roteia por hostname:
- `api.oikos.company` → `api:3333`
- `oikos.company` → `web:3000`
- `grafana.oikos.company` → proxy pra `grafana` na `E2.1.Micro` (via IP privado), atrás de **Cloudflare Access**
- `minio.oikos.company` → console do MinIO (porta 9001), também atrás de **Cloudflare Access**. A API S3 do MinIO (porta 9000) nunca é exposta — só o container `api` fala com ela internamente (a rota `GET /storage/*` já faz proxy dos arquivos).

TLS via certificado Cloudflare Origin CA. Security List da OCI libera 443 só pros ranges de IP do Cloudflare (DNS proxied/orange-cloud) — sem Cloudflare Tunnel em produção.

**Bootstrap das VMs**: `cloud-init` (via `user_data` do Terraform) — instala Docker, cria usuário `deploy` (chave SSH própria, grupo `docker`), hardening básico de SSH, e (só na `E2.1.Micro`) cria e ativa swap file de 8-10GB. Não inclui secrets nem os compose files — isso é responsabilidade do deploy, não do provisionamento (declarativo e idempotente, escolhido no lugar de `remote-exec` justamente pra nunca duplicar/reprovisionar errado).

**Terraform**: providers OCI + Cloudflare. State remoto no **Terraform Cloud** (free tier — confirmado ~$0/mês pro tamanho deste projeto: até 500 recursos grátis, usamos ~12-16; 1 run concorrente não é limitante pra um projeto solo). Terraform Cloud também resolve um problema que um bucket OCI Object Storage por si só não resolveria: o backend `s3` do Terraform depende de lock via DynamoDB pra evitar `apply` concorrente corromper o state — a OCI não tem equivalente nativo. VCS-driven: Terraform Cloud conecta direto no repo `devops` e roda plan/apply sozinho a cada push relevante em `infra/terraform/` — sem workflow do GitHub Actions pra isso. Credenciais OCI/Cloudflare ficam só no Terraform Cloud (workspace variables sensitive), nunca em secret do GitHub. Módulos: `compute` (as 2 VMs), `network` (VCN, subnet, Security Lists), `dns` (registros Cloudflare), `storage` (bucket Object Storage só pra backups — não pro state).

**Deploy (`deploy.yml` no `devops`)**: acionado por `repository_dispatch` de `api` ou `web`, com `event_type` **`api-production`** / **`web-production`** (mesmo nome do job e do Environment do GitHub correspondente, por consistência). Fluxo por job:
1. Build arm64 (Buildx + QEMU) da imagem correspondente.
2. Push pro GHCR (GitHub Packages) — **imagem privada**, autenticada via PAT fine-grained (`read:packages`) guardado como secret.
3. SSH na `A1.Flex`.
4. Só pro job `api-production`: `pg_dump` de segurança do Postgres, depois `docker compose run --rm api npx prisma migrate deploy` — **passo separado, antes de trocar o container**. Se falhar, o deploy aborta e o container antigo continua servindo (evita janela de indisponibilidade total). O `CMD` do `Dockerfile.prod` do `api` deixa de rodar a migration sozinho — vira só `node dist/server.js`.
5. `docker compose pull <serviço> && up -d <serviço>` — **targeted**, nunca a stack inteira (um deploy do `web` nunca reinicia `api`/Postgres/Redis/MinIO, e vice-versa).

**Primeiro deploy**: não existe stack rodando até a primeira execução — como secrets/compose files não vêm do `cloud-init`, a primeira subida é um `workflow_dispatch` manual do `deploy.yml`, não um `repository_dispatch`.

**Secrets do GitHub Actions** — sem serviço de secret-manager dedicado neste MVP (GitHub Secrets já resolve no tamanho atual):
- **Nível repo (`devops`)**, compartilhado pelos dois jobs: `SSH_DEPLOY_KEY`, `GHCR_PAT`, `CLOUDFLARE_ORIGIN_CERT`/`CLOUDFLARE_ORIGIN_KEY`. `VM_HOST` fica como *Variable* (não é sensível).
- **Environment `api-production`** (só o job `api-production` declara acesso): `DATABASE_URL`, `JWT_SECRET`, `REDIS_URL`, `MINIO_ACCESS_KEY`/`MINIO_SECRET_KEY`, credenciais Google/Apple de teste, `ADMIN_USERNAME`/`ADMIN_PASSWORD`.
- **Environment `web-production`** (só o job `web-production` declara acesso): vazio por enquanto, pronto pra quando o `web` precisar de secrets próprios.
- **Nível repo (`api` e `web`)**: cada um só tem 1 secret — PAT fine-grained próprio (não compartilhado entre os dois) pra disparar `repository_dispatch` no `devops`, escopo mínimo, revogável independentemente.
- Os **valores** dos secrets são cadastrados diretamente pelo usuário (`gh secret set` ou UI do GitHub) — nunca digitados/manipulados pelo assistente, pra não passarem pelo contexto/logs da sessão. O assistente só escreve estrutura (YAML dos workflows, criação dos Environments), nunca valores.

**Backup**: Postgres + Redis, diário, retendo 7 dias, indo pro Oracle Object Storage (20GB Always Free, pool separado dos 200GB de Block Volume). MinIO fica fora do backup neste MVP — plano pós-MVP é mover MinIO pra storage externo (Oracle ou AWS).

**Storage**: `A1.Flex` ~150GB, `E2.1.Micro` ~50GB de boot volume (incluindo o swap file de 8-10GB) — dentro dos 200GB compartilhados do Always Free.

**Restrição chave**: tudo cabe no Always Free — 200GB block storage compartilhado, 2 OCPU/12GB (A1.Flex), 1GB/⅛ OCPU (E2.1.Micro), 20GB Object Storage separado, 10TB egress/mês, Terraform Cloud ~$0/mês.

Valores e limites detalhados (Always Free, Terraform Cloud, GHCR, Cloudflare) documentados em [`docs/infrastructure.md`](../../docs/infrastructure.md).

## Modelo de Dados

Este épico **não altera o schema de aplicação** — nenhuma migration nova do Prisma faz parte do escopo, nenhuma entidade de domínio é criada ou modificada. É puramente infraestrutura.

A única estrutura de dados nova é o **artefato de backup** no Oracle Object Storage:

- **Bucket**: `oikos-backups`, provisionado pelo módulo `storage` do Terraform.
- **Convenção de nomes** (prefixo por serviço):
  - `postgres/oikos-postgres-{YYYYMMDD-HHmmss}.dump.gz`
  - `redis/oikos-redis-{YYYYMMDD-HHmmss}.rdb.gz`
- **Retenção**: Object Lifecycle Policy nativa da OCI (não script customizado) — regra por prefixo, deleta objetos com mais de 7 dias. Definida declarativamente no mesmo módulo Terraform que cria o bucket. Custo da automação: irrelevante no nosso volume (~120 requisições/mês de um total de 50.000 grátis) — detalhado em `docs/infrastructure.md`.

## Arquitetura de Componentes

### `oikos/api`
| Arquivo | Mudança |
|---|---|
| `.github/workflows/ci.yml` | Novo — format → lint → unit → integration → e2e → (em `production`) tag SemVer automática → `repository_dispatch` (`event_type: api-production`) pro `devops` |
| `Dockerfile.prod`, `docker-compose.prod.yml` | Removidos — migram pro `devops` |
| `Dockerfile.prod` (a versão que migra) | `CMD` deixa de rodar `prisma migrate deploy` — vira só `node dist/server.js`. Migration passa a ser passo externo do deploy |
| `README.md`, `plans/self-hosted-infra/*` | Atualizar referências à simulação local de produção removida |

### `oikos/mobile`
| Arquivo | Mudança |
|---|---|
| `.github/workflows/ci.yml` | Novo — format → lint → test → (em `production`) tag SemVer automática. Sem `repository_dispatch` (fora do escopo de deploy) |

### `oikos/web`
| Arquivo | Mudança |
|---|---|
| `next.config.ts` | ✅ já feito — `output: "standalone"` |
| `.github/workflows/ci.yml` | Novo — format → lint → test → (em `production`) tag SemVer automática → `repository_dispatch` (`event_type: web-production`) pro `devops` |

### `oikos/devops`
| Arquivo | Mudança |
|---|---|
| `infra/terraform/compute/` | Novo — VMs `A1.Flex` + `E2.1.Micro`, cloud-init (Docker, usuário `deploy`, swap na `E2.1.Micro`) |
| `infra/terraform/network/` | Novo — VCN, subnet privada, Security Lists (443 só Cloudflare) |
| `infra/terraform/dns/` | Novo — registros Cloudflare (`api`, `oikos.company`, `grafana`, `minio`) + políticas Cloudflare Access |
| `infra/terraform/storage/` | Novo — bucket `oikos-backups` + Lifecycle Policy |
| `infra/terraform/backend.tf` | Novo — aponta pro workspace do Terraform Cloud |
| `docker/Dockerfile.api.prod` | Migrado do `api`, `CMD` simplificado (ver acima) |
| `docker/Dockerfile.web.prod` | ✅ já feito |
| `docker/docker-compose.prod.yml` | Novo — api, web, postgresql, redis, minio, createbuckets, nginx, Alloy/cAdvisor/node-exporter |
| `nginx/nginx.conf` | Novo — roteamento por hostname + TLS Origin CA |
| `observability/docker-compose.observability.yml` | Ajustado — limites re-tunados pra ~875MB (`E2.1.Micro`), Tempo/Alertmanager mantidos |
| `.github/workflows/deploy.yml` | Novo — jobs `api-production`/`web-production` (Environments homônimos), build arm64, push GHCR, SSH deploy (backup → migrate deploy → pull/up targeted) |
| `scripts/backup-postgres.sh`, `scripts/backup-redis.sh` | Novo — cron/systemd timer diário, upload pro Object Storage |
| `scripts/migrate-data.sh` | Novo — dump/restore Postgres + `mc mirror` MinIO, uso único no cutover |
| `docs/infrastructure.md`, `docs/architecture-diagrams.md` | ✅ já feitos |

### Interfaces entre componentes
- `api`/`web` → `devops`: `repository_dispatch` com `event_type` (`api-production`/`web-production`) + payload `{version, sha}`.
- `deploy.yml` → VM: SSH, usuário `deploy`, executa `docker compose` no diretório onde `docker-compose.prod.yml` foi sincronizado.
- `A1.Flex` → `E2.1.Micro`: IP privado da VCN, sem porta pública (Prometheus remote_write, Loki push, Tempo OTLP gRPC).
- `deploy.yml` → GHCR: PAT fine-grained (`read:packages`/`write:packages`), imagem privada.
