# T1 — `api`: CI + Versionamento

**Status**: Em andamento (dev/simulation profiles + scripts npm já feitos)
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
- [x] Step de `repository_dispatch` pro `oikos-circular-environment/devops`, `event_type: api-production`, payload `{version, sha}`
- [ ] Criar PAT fine-grained escopado só pro repo `devops`, permissão mínima pra disparar dispatch (feito pelo usuário, fora da sessão do assistente — `gh` CLI não cria PAT fine-grained, só a UI)
- [ ] Cadastrar o PAT como secret `DEVOPS_DISPATCH_PAT` no repo `api` (usuário cadastra o valor)
- [ ] Validar workflow rodando de verdade num PR de teste
- [x] Remover `docker-compose.prod.yml` do repo (migrado pra `devops/docker/docker-compose.prod.yml`, T6 concluída antes desta remoção)
- [x] Remover `Dockerfile.prod` do repo (migrado pra `devops/docker/Dockerfile.api.prod`, CMD simplificado — migration não roda mais sozinha)
- [x] Remover `.env.prod.example` do repo (equivalente migrado pra `devops/docker/.env.prod.example`)
- [x] `README.md` conferido — nunca documentou a simulação de produção, nada pra atualizar
- [x] `plans/self-hosted-infra/*` conferido — não referenciam `docker-compose.prod.yml`/`Dockerfile.prod` (escopo daquele épico era só ambiente de dev local), nada pra atualizar

## Definição de Pronto

Um PR de teste, ao ser mergeado em `production`, cria a tag SemVer sozinho e dispara o `repository_dispatch` visível na aba Actions do `devops` (mesmo que o `devops` ainda não tenha um `deploy.yml` pronto pra reagir).
