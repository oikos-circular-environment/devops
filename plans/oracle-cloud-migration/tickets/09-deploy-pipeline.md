# T9 — `devops`: Deploy Pipeline

**Status**: Não iniciado
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
- [ ] Criar Environment `api-production` no repo `devops`
- [ ] Criar Environment `web-production` no repo `devops`
- [ ] Cadastrar secrets de nível repo: `SSH_DEPLOY_KEY` (usuário cadastra)
- [ ] Cadastrar secrets de nível repo: `GHCR_PAT` (`read:packages`, usuário cadastra)
- [ ] Cadastrar secrets de nível repo: `CLOUDFLARE_ORIGIN_CERT`/`CLOUDFLARE_ORIGIN_KEY` (usuário cadastra, de T5)
- [ ] Cadastrar `VM_HOST` como Variable (não secret)
- [ ] Cadastrar secrets do Environment `api-production`: `DATABASE_URL`, `JWT_SECRET`, `REDIS_URL`, `MINIO_ACCESS_KEY`/`MINIO_SECRET_KEY`, credenciais Google/Apple de teste, `ADMIN_USERNAME`/`ADMIN_PASSWORD` (usuário cadastra)
- [ ] Environment `web-production` criado e vazio (pronto pra quando o `web` precisar de secrets próprios)

**Workflow `.github/workflows/deploy.yml`:**
- [ ] Trigger `repository_dispatch` com `event_type: api-production`
- [ ] Trigger `repository_dispatch` com `event_type: web-production`
- [ ] Trigger `workflow_dispatch` manual (necessário pro primeiro deploy)
- [ ] Job `api-production` com `environment: api-production`
- [ ] Job `web-production` com `environment: web-production`
- [ ] Step: build arm64 (Buildx + QEMU) da imagem correspondente
- [ ] Step: push pra GHCR (imagem privada, autenticada via `GHCR_PAT`)
- [ ] Step: SSH na `A1.Flex` com `SSH_DEPLOY_KEY`
- [ ] Step (só `api-production`): `pg_dump` de segurança do Postgres antes de qualquer mudança
- [ ] Step (só `api-production`): `docker compose run --rm api npx prisma migrate deploy` — se falhar, workflow para aqui, container antigo continua servindo
- [ ] Step: `docker compose pull <serviço> && up -d <serviço>` — targeted, nunca a stack inteira
- [ ] Confirmar que um deploy do `web` nunca reinicia `api`/Postgres/Redis/MinIO e vice-versa

## Definição de Pronto

Disparar `workflow_dispatch` manualmente builda, publica e implanta com sucesso pela primeira vez. Depois disso, um merge de teste em `production` do `api` (ou `web`) dispara o `repository_dispatch` e o deploy acontece automaticamente, de ponta a ponta, sem intervenção manual.
