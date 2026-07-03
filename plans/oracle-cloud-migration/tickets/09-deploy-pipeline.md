# T9 — `devops`: Deploy Pipeline

**Status**: **Pronta.** Fluxo automático completo validado de ponta a ponta pra `api` e `web`: merge em `production` → CI → tag SemVer → `repository_dispatch` → `deploy.yml` builda, publica e implanta sozinho, sem intervenção manual. `api` rodando `v0.0.2`, `web` rodando `v0.0.3` — ambos vieram do pipeline automático real, não de teste manual. 4 bugs achados testando contra a infra de verdade (notas 5-8 abaixo), todos corrigidos.

**Gaps encontrados e resolvidos ao escrever o workflow** (não estavam no desenho original):
1. **`SOURCE_REPO_PAT` — novo secret, não estava no checklist original.** O `deploy.yml` builda a imagem a partir do código-fonte do `api`/`web`, que vivem em repositórios *separados* do `devops`. O `repository_dispatch` só carrega `{version, sha}` no payload, não o código — o workflow precisa de um `actions/checkout` cross-repo pra pegar o source, e isso exige um PAT com `Contents: read` nos repos `api` e `web` (fine-grained, escopo mínimo). Sem isso o build não tem o que buildar.
2. **Nomes de variável do `.env.prod` não batem com o checklist original.** O checklist pedia secrets chamados `DATABASE_URL`/`REDIS_URL`, mas o `.env.prod.example` (já criado na T6) usa `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB`/`REDIS_PASSWORD` (peças separadas, não uma URL montada) — segui o `.env.prod.example`, que é a fonte de verdade já validada, e corrigi a lista abaixo.
3. **`OBSERVABILITY_PRIVATE_IP` — variável que tinha ficado como pendência solta numa conversa anterior** (o `.env.prod.example` tem um placeholder `<IP-PRIVADO-E2.1.MICRO>` pras URLs de observabilidade). Cadastrada agora como Variable, mesmo padrão do `VM_HOST`.
4. **`GOOGLE_ACCOUNT_EMAIL`/`PASSWORD` e `APPLE_ACCOUNT_EMAIL`/`PASSWORD` removidos do deploy.** São credenciais usadas só pelos seeds de conta de teste (`prisma/seeds/google-account.seed.ts`/`apple-account.seed.ts`), não pelo runtime da API — mas o schema Zod do `api` (`src/env/index.ts`) exigia elas obrigatoriamente pra API subir, o que forçaria o deploy a sempre carregar credencial de teste em produção. Corrigido em duas pontas: schema do `api` marcado `.optional()` (com guarda equivalente nos dois seeds, pra não quebrar em `string | undefined`), e o `deploy.yml`/`​.env.prod.example` pararam de mencionar essas 4 variáveis. O seed continua existindo — só passa a ser responsabilidade do usuário rodar manualmente, com calma, escolhendo o que sobe (nunca inclui `users.seed.ts`, que povoa usuários fake).
5. **`--env-file .env.prod` faltando em todo `docker compose`** — Compose só carrega `.env` automaticamente, não `.env.prod`. Achado ao fazer o bootstrap manual real da stack (T6): toda substituição de variável (`${API_VERSION}`, `${POSTGRES_USER}` etc.) caía em branco/`latest`. Corrigido em todos os `docker compose` do `deploy.yml`.
6. **Sincronização pra VM não incluía `observability/`** — o `scp` só copiava `docker/`, `nginx/`, `scripts/`, mas o `docker-compose.prod.yml` monta `../observability/alloy/alloy-prod.alloy` como volume do `alloy`. Sem o diretório, o Docker cria um diretório vazio no lugar do arquivo esperado e o `alloy` falha ao montar. Corrigido — `observability/` agora faz parte do `scp`.
7. **Placeholder `__OBS_VM_PRIVATE_IP__` do `nginx.conf` nunca era substituído** — o comentário do próprio `nginx.conf` já dizia que a substituição seria via `sed` no deploy, mas esse passo nunca existiu no `deploy.yml`. Sem ele, o `nginx` nem sobe (`host not found in upstream`). Corrigido — novo passo de `sed` logo após sincronizar os arquivos, usando `vars.OBSERVABILITY_PRIVATE_IP` (já cadastrada).
8. **Build cross-arch via QEMU (`docker/setup-qemu-action`) travava com `qemu: uncaught target signal 4 (Illegal instruction) - core dumped`** durante o `npm ci`, e depois do crash o BuildKit não reportava falha — ficava preso indefinidamente (só terminou quando cancelado manualmente após ~20min). Achado no primeiro `workflow_dispatch` real de ponta a ponta. Corrigido trocando `runs-on: ubuntu-latest` por `runs-on: ubuntu-24.04-arm` (runner arm64 nativo do GitHub, disponível pra repos privados desde 29/01/2026) nos dois jobs — build nativo, sem emulação, sem QEMU. `docker/setup-qemu-action` removido (não é mais necessário).
**Repositório**: `oikos-circular-environment/devops`

## Escopo

O `deploy.yml` que reage aos `repository_dispatch` do `api`/`web`, builda e implanta — sem gate de aprovação manual. Inclui toda a estrutura de secrets/Environments do GitHub.

## Fora de escopo

Os arquivos de compose em si (T6); provisionamento da VM (T4). Os **valores** dos secrets são cadastrados pelo usuário, nunca pelo assistente.

## Referências de spec

- `00-epic-brief.md` §Versionamento e Fluxo de Release (Deploy no devops)
- `04-tech-plan.md` §Abordagem Arquitetural (Deploy, Secrets do GitHub Actions)

## Dependências

T1, T3 (dispatch precisa existir do lado de origem), T6 (precisa dos compose files), T4 (precisa da VM).

## Checklist

**Estrutura no GitHub:**
- [x] Criar Environment `api-production` no repo `devops`
- [x] Criar Environment `web-production` no repo `devops` (vazio por enquanto, pronto pra quando o `web` precisar de secrets próprios)
- [x] Cadastrar `VM_HOST` como Variable (não secret) — `134.65.229.35`
- [x] Cadastrar `OBSERVABILITY_PRIVATE_IP` como Variable (não secret) — `10.0.2.37` (resolve o placeholder `<IP-PRIVADO-E2.1.MICRO>` do `.env.prod.example`)
- [x] Cadastrar secrets de nível repo: `SSH_DEPLOY_KEY` — chave real da `A1.Flex`/`E2.1.Micro`
- [x] Cadastrar secrets de nível repo: `GHCR_PAT` (`write:packages`, token classic dedicado)
- [x] Cadastrar secrets de nível repo: `SOURCE_REPO_PAT` (fine-grained, `Contents: read` nos repos `api` e `web` — **novo, não estava no desenho original**, ver nota acima)
- [x] Cadastrar secrets de nível repo: `CLOUDFLARE_ORIGIN_CERT`/`CLOUDFLARE_ORIGIN_KEY` — valores reais de T5 (`terraform output -raw origin_certificate_pem`/`origin_private_key_pem`)
- [x] Cadastrar secrets do Environment `api-production`: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `MINIO_ACCESS_KEY`/`MINIO_SECRET_KEY`, `JWT_SECRET`, `ADMIN_USERNAME`/`ADMIN_PASSWORD` — valores reais já validados em produção no bootstrap do T6 (nomes corrigidos pra bater com `.env.prod.example`; `GOOGLE_ACCOUNT_*`/`APPLE_ACCOUNT_*` removidos do deploy, ver nota 4 acima — seed manual, fora do CI)

**Workflow `.github/workflows/deploy.yml`:**
- [x] Trigger `repository_dispatch` com `event_type: api-production`
- [x] Trigger `repository_dispatch` com `event_type: web-production`
- [x] Trigger `workflow_dispatch` manual, com inputs `service`/`sha`/`version` (necessário pro primeiro deploy)
- [x] Job `api-production` com `environment: api-production`
- [x] Job `web-production` com `environment: web-production`
- [x] Checkout cross-repo do código-fonte (`api`/`web`) via `SOURCE_REPO_PAT`, no SHA do `repository_dispatch`
- [x] Step: build arm64 (Buildx + QEMU) da imagem correspondente
- [x] Step: push pra GHCR (imagem privada, autenticada via `GHCR_PAT`)
- [x] Step: SSH na `A1.Flex` com `SSH_DEPLOY_KEY`
- [x] Step: sincroniza `docker/`, `nginx/`, `observability/`, `scripts/` pra VM (primeiro deploy não tem cloud-init com esses arquivos — T4 é só provisionamento; `observability/` e o `sed` do placeholder do IP adicionados após achado no bootstrap real da T6, ver nota 6/7 acima)
- [x] Step: renderiza `.env.prod` a partir dos secrets do Environment (só no job `api-production` — o `web-production` só atualiza a linha `WEB_VERSION` via `sed`, nunca mexe nos segredos do outro Environment, que ele nem teria acesso)
- [x] Step: materializa `CLOUDFLARE_ORIGIN_CERT`/`CLOUDFLARE_ORIGIN_KEY` em `/opt/oikos/docker/certs/` (nunca commitados, ver `.gitignore`)
- [x] Step (só `api-production`): `pg_dump` de segurança do Postgres antes de qualquer mudança (chama `scripts/backup-postgres.sh` da T8)
- [x] Step (só `api-production`): `docker compose run --rm api npx prisma migrate deploy` — se falhar, workflow para aqui (sem `continue-on-error`), container antigo continua servindo
- [x] Step: `docker compose pull <serviço> && up -d <serviço>` — targeted, nunca a stack inteira
- [x] Confirmar que um deploy do `web` nunca reinicia `api`/Postgres/Redis/MinIO e vice-versa — jobs completamente separados, cada um só roda `pull`/`up -d` do seu próprio serviço

## Melhorias futuras (fora do escopo agora — prioridade é validar o pipeline de ponta a ponta primeiro)

- [ ] **Modularizar `api-production`/`web-production` em jobs separados** (`build` → `sync` → `backup` → `migrate` → `deploy-container`, com `needs:` entre eles). Hoje é um job só — se qualquer step falhar (ex: backup), um "Re-run failed jobs" refaz tudo do zero, incluindo o build da imagem (o mais caro em tempo). Com jobs separados, o "Re-run failed jobs" do GitHub Actions só re-executa o job que falhou em diante, reaproveitando o resultado dos jobs já bem-sucedidos (a imagem já publicada no GHCR não precisa ser rebuilada).
- [x] **Job `infra-production` novo, independente de release do `api`/`web`.** Feito em [T11](./11-deploy-pipeline-infra-only.md) — job disparado por `push` filtrado nos paths `nginx/**`, `observability/**`, `docker/docker-compose.prod.yml`, `scripts/**`, sem build de imagem. Validado de ponta a ponta.
- [x] **`deploy.yml` nunca recarrega o nginx.** Feito em [T11](./11-deploy-pipeline-infra-only.md) — `up -d --force-recreate --no-deps nginx alloy` nos três jobs (`reload`/`restart` não bastavam, ver achado de bind mount de arquivo único no ticket).

## Definição de Pronto

Disparar `workflow_dispatch` manualmente builda, publica e implanta com sucesso pela primeira vez. Depois disso, um merge de teste em `production` do `api` (ou `web`) dispara o `repository_dispatch` e o deploy acontece automaticamente, de ponta a ponta, sem intervenção manual.

**Confirmado de verdade em 2026-07-03**: `workflow_dispatch` manual (`service=api`) completou com sucesso — build nativo arm64, backup do Postgres, migration, e deploy targeted do container `api`, tudo de ponta a ponta. Depois disso, o fluxo **automático** também foi validado: merge real em `production` do `web` e do `api` disparou `repository_dispatch` → `deploy.yml` sozinho, sem `workflow_dispatch` manual. `api` rodando `v0.0.2`, `web` rodando `v0.0.3`.

### Nota 9 — pegadinha na criação do `DEVOPS_DISPATCH_PAT`

Na primeira tentativa, o `repository_dispatch` falhou com 403/404 mesmo com o secret cadastrado. Causa: ao criar o fine-grained token, é fácil confundir **qual repositório selecionar** — o token *mora* no repo `api`/`web` (é lá que vira secret), mas precisa dar acesso *ao repositório* `devops` (é pra lá que ele escreve o evento). Selecionar `api`/`web` como "Repository access" (em vez de `devops`) dá 404 (token não enxerga o repo alvo). Selecionar `devops` mas deixar a permissão de `Contents` como `Read-only` (em vez de `Read and write`) dá 403 (enxerga o repo, mas não tem permissão de escrever o evento). O passo a passo corrigido está na seção "Guia" dos tickets T1/T3.
