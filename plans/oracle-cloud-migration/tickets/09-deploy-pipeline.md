# T9 — `devops`: Deploy Pipeline

**Status**: Escrito e validado localmente (YAML), na branch `feature/t9-deploy-pipeline`. Estrutura do GitHub (Environments + variáveis não-secretas) já criada de verdade. Falta cadastrar os valores dos secrets (usuário) e testar o `workflow_dispatch` de ponta a ponta (deferido pra revisão final, ticket 99).

**Gaps encontrados e resolvidos ao escrever o workflow** (não estavam no desenho original):
1. **`SOURCE_REPO_PAT` — novo secret, não estava no checklist original.** O `deploy.yml` builda a imagem a partir do código-fonte do `api`/`web`, que vivem em repositórios *separados* do `devops`. O `repository_dispatch` só carrega `{version, sha}` no payload, não o código — o workflow precisa de um `actions/checkout` cross-repo pra pegar o source, e isso exige um PAT com `Contents: read` nos repos `api` e `web` (fine-grained, escopo mínimo). Sem isso o build não tem o que buildar.
2. **Nomes de variável do `.env.prod` não batem com o checklist original.** O checklist pedia secrets chamados `DATABASE_URL`/`REDIS_URL`, mas o `.env.prod.example` (já criado na T6) usa `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB`/`REDIS_PASSWORD` (peças separadas, não uma URL montada) — segui o `.env.prod.example`, que é a fonte de verdade já validada, e corrigi a lista abaixo.
3. **`OBSERVABILITY_PRIVATE_IP` — variável que tinha ficado como pendência solta numa conversa anterior** (o `.env.prod.example` tem um placeholder `<IP-PRIVADO-E2.1.MICRO>` pras URLs de observabilidade). Cadastrada agora como Variable, mesmo padrão do `VM_HOST`.
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
- [ ] Cadastrar secrets de nível repo: `SSH_DEPLOY_KEY` (usuário cadastra)
- [ ] Cadastrar secrets de nível repo: `GHCR_PAT` (`read:packages`, usuário cadastra)
- [ ] Cadastrar secrets de nível repo: `SOURCE_REPO_PAT` (fine-grained, `Contents: read` nos repos `api` e `web` — usuário cadastra; **novo, não estava no desenho original**, ver nota acima)
- [ ] Cadastrar secrets de nível repo: `CLOUDFLARE_ORIGIN_CERT`/`CLOUDFLARE_ORIGIN_KEY` (usuário cadastra, de T5)
- [ ] Cadastrar secrets do Environment `api-production`: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `MINIO_ACCESS_KEY`/`MINIO_SECRET_KEY`, `JWT_SECRET`, `GOOGLE_ACCOUNT_EMAIL`/`GOOGLE_ACCOUNT_PASSWORD`, `APPLE_ACCOUNT_EMAIL`/`APPLE_ACCOUNT_PASSWORD`, `ADMIN_USERNAME`/`ADMIN_PASSWORD` (usuário cadastra — nomes corrigidos pra bater com `.env.prod.example`, ver nota acima)

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
- [x] Step: sincroniza `docker/`, `nginx/`, `scripts/` pra VM (primeiro deploy não tem cloud-init com esses arquivos — T4 é só provisionamento)
- [x] Step: renderiza `.env.prod` a partir dos secrets do Environment (só no job `api-production` — o `web-production` só atualiza a linha `WEB_VERSION` via `sed`, nunca mexe nos segredos do outro Environment, que ele nem teria acesso)
- [x] Step: materializa `CLOUDFLARE_ORIGIN_CERT`/`CLOUDFLARE_ORIGIN_KEY` em `/opt/oikos/docker/certs/` (nunca commitados, ver `.gitignore`)
- [x] Step (só `api-production`): `pg_dump` de segurança do Postgres antes de qualquer mudança (chama `scripts/backup-postgres.sh` da T8)
- [x] Step (só `api-production`): `docker compose run --rm api npx prisma migrate deploy` — se falhar, workflow para aqui (sem `continue-on-error`), container antigo continua servindo
- [x] Step: `docker compose pull <serviço> && up -d <serviço>` — targeted, nunca a stack inteira
- [x] Confirmar que um deploy do `web` nunca reinicia `api`/Postgres/Redis/MinIO e vice-versa — jobs completamente separados, cada um só roda `pull`/`up -d` do seu próprio serviço

## Definição de Pronto

Disparar `workflow_dispatch` manualmente builda, publica e implanta com sucesso pela primeira vez. Depois disso, um merge de teste em `production` do `api` (ou `web`) dispara o `repository_dispatch` e o deploy acontece automaticamente, de ponta a ponta, sem intervenção manual.
