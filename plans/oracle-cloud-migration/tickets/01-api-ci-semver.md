# T1 — `api`: CI + Versionamento

**Status**: **Pronta.** CI completo (lint/unit/integration/e2e) e pipeline de deploy automático validados de ponta a ponta em 2026-07-03 — merge real em `production` disparou tag SemVer + `repository_dispatch` + deploy sozinho, sem intervenção manual (`api` rodando `v0.0.2` em produção).
**Repositório**: `oikos-circular-environment/api`

## Escopo

CI completo do repo (format → lint → unit → integration → e2e), tag SemVer automática em `production`, e o disparo de `repository_dispatch` que avisa o `devops` sobre uma nova versão. Remoção dos artefatos de infra que hoje moram no `api` por engano. Inclui também a separação entre stack de desenvolvimento (hot-reload) e stack de simulação local de produção, e o uso do `docker-compose.test.yml` existente dentro do próprio `ci.yml`.

## Fora de escopo

Qualquer lógica de deploy, build de imagem Docker ou infraestrutura — isso é 100% do `devops` (ver T6, T9).

## Referências de spec

- `00-epic-brief.md` §Escopo por Repositório, §Versionamento e Fluxo de Release
- `04-tech-plan.md` §Arquitetura de Componentes (`oikos/api`)

## Dependências

Nenhuma — pode começar imediatamente.

## Checklist

**Dev / simulação local (✅ feito):**
- [x] `Dockerfile.dev` multi-stage: stage `dev` (hot-reload, como antes) + stage `simulation` (build imutável, `NODE_ENV=production`, sem hot-reload, migration fora do `CMD`)
- [x] `docker-compose.dev.yml` com `profiles: ["dev"]` no serviço `api` e `profiles: ["simulation"]` no novo serviço `api-sim` (limite 512MB/1 CPU, igual à produção) — mutuamente exclusivos, validados via `docker compose config`
- [x] Scripts no `package.json`: `dev:up`, `dev:down`, `sim:migrate`, `sim:up`, `sim:down`
- [x] Documentado que a simulação é uma aproximação local, não a imagem real de deploy (essa vive em `devops/docker/Dockerfile.api.prod`)

**CI (`.github/workflows/ci.yml`, ✅ escrito — falta secret/PAT e validar rodando):**
- [x] Job `format → lint → unit` (`npx biome ci .` + `npm test`)
- [x] Job de integração: sobe `docker-compose.test.yml` via `npm run test:infra:up` → `npm run test:integration` → `test:infra:down`. Mesma infra usada localmente, sem redefinir em YAML nativo do Actions
- [x] Job de e2e: mesma abordagem, com `npm run test:e2e`
- [x] Job só falha o merge se algum desses passos falhar (gate de qualidade — `needs:` encadeado)
- [x] Step de tag SemVer automática (`mathieudutour/github-tag-action`, `default_bump: patch`) ao detectar push em `production`
- [x] MAJOR/MINOR continuam manuais (não automatizado — `default_bump: patch` sempre)
- [x] Step de `repository_dispatch` pro `oikos-circular-environment/devops`, `event_type: api-production`, payload `{version, sha}` — [PR #34](https://github.com/oikos-circular-environment/api/pull/34) adiciona `-f`/`--fail` no `curl`; sem isso, uma resposta HTTP de erro do GitHub (ex: 401 por secret ausente) não falhava o step, mascarando o problema (achado ao investigar o mesmo bug real no `web`, ver T3)
- [x] Criar PAT fine-grained escopado só pro repo `devops`, `Contents: Read and write` (feito pelo usuário) — na primeira tentativa errou o repositório selecionado (apontou pro `api` em vez do `devops`, dando 404) e depois a permissão (`Read-only` em vez de `Read and write`, dando 403); corrigido recriando o token do zero
- [x] Cadastrar o PAT como secret `DEVOPS_DISPATCH_PAT` no repo `api`
- [x] Validar workflow rodando de verdade num PR de teste — merge real em `production` (2026-07-03) disparou `repository_dispatch` sozinho, `devops` buildou e implantou `v0.0.2` automaticamente, sem `workflow_dispatch` manual
- [x] Remover `docker-compose.prod.yml` do repo (migrado pra `devops/docker/docker-compose.prod.yml`, T6 concluída antes desta remoção)
- [x] Remover `Dockerfile.prod` do repo (migrado pra `devops/docker/Dockerfile.api.prod`, CMD simplificado — migration não roda mais sozinha)
- [x] Remover `.env.prod.example` do repo (equivalente migrado pra `devops/docker/.env.prod.example`)
- [x] `README.md` conferido — nunca documentou a simulação de produção, nada pra atualizar
- [x] `plans/self-hosted-infra/*` conferido — não referenciam `docker-compose.prod.yml`/`Dockerfile.prod` (escopo daquele épico era só ambiente de dev local), nada pra atualizar

## Definição de Pronto

Um PR de teste, ao ser mergeado em `production`, cria a tag SemVer sozinho e dispara o `repository_dispatch` visível na aba Actions do `devops` (mesmo que o `devops` ainda não tenha um `deploy.yml` pronto pra reagir).

## Guia: criar o PAT fine-grained

**O que é**: um Personal Access Token autentica chamadas de API do GitHub. "Fine-grained" é o tipo granular — em vez de acesso a todos os seus repos (PAT clássico), você escolhe exatamente qual repositório e qual permissão dentro dele. Não tem relação com "criar variáveis no projeto".

**Por que precisa disso aqui**: o `ci.yml` do `api`, ao terminar, precisa chamar a API `repos/oikos-circular-environment/devops/dispatches` pra avisar o `devops` que saiu versão nova. O `GITHUB_TOKEN` automático que todo workflow ganha de graça só tem permissão **dentro do próprio repositório onde roda** — não serve pra mexer no `devops`, que é outro repo. Por isso precisa de um token à parte, com permissão explícita sobre o `devops`. Confirmado: `repository_dispatch` exige a permissão **"Contents: Read and write"** no repositório de destino.

**Passo a passo**:
1. GitHub → avatar → **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens** → **Generate new token**
2. **Resource owner**: `oikos-circular-environment`
3. **Repository access**: "Only select repositories" → escolher só **`devops`**
4. **Permissions** → **Repository permissions** → **Contents**: `Read and write`
5. **Generate token** → copiar o valor (só aparece uma vez)
6. Se a organização exigir aprovação (**Require administrator approval** ligado): ir em **Personal access tokens → Pending requests** nas settings da organização e aprovar
7. Cadastrar como secret, via CLI (valor nunca passa pelo assistente):
   ```bash
   gh secret set DEVOPS_DISPATCH_PAT --repo oikos-circular-environment/api
   ```
   ou pela UI: repo **`api`** → **Settings** → **Secrets and variables** → **Actions** → **New repository secret** → nome `DEVOPS_DISPATCH_PAT` → colar o valor

**Importante**: gerar um token **separado** pro `web` (T3) — não reaproveitar este mesmo token nos dois repos, mesmo que a permissão seja idêntica (facilita revogar um sem afetar o outro).
