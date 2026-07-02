# T3 — `web`: CI + Versionamento

**Status**: Em andamento (`next.config.ts` já ajustado)
**Repositório**: `oikos-circular-environment/web`

## Escopo

CI do repo (format → lint → test), tag SemVer automática em `production`, e o disparo de `repository_dispatch` que avisa o `devops` sobre uma nova versão — mesmo padrão do `api` (T1).

## Fora de escopo

Dockerfile/compose de produção — vivem no `devops` (T6). `Dockerfile.web.prod` já foi criado lá.

## Referências de spec

- `00-epic-brief.md` §Escopo por Repositório, §Versionamento e Fluxo de Release
- `04-tech-plan.md` §Arquitetura de Componentes (`oikos/web`)

## Dependências

Nenhuma — pode continuar/terminar imediatamente.

## Checklist

- [x] `next.config.ts` com `output: "standalone"`
- [x] Criar `.github/workflows/ci.yml` com jobs `format → lint → build` (**gap encontrado**: não há test runner configurado no repo — sem vitest/jest, sem script `test`. `build` usado como gate provisório, marcado com TODO no workflow. Precisa de decisão sobre framework de teste, fora do escopo desta ticket)
- [x] Job só falha o merge se algum desses passos falhar
- [x] Step de tag SemVer automática (`mathieudutour/github-tag-action`, `default_bump: patch`) ao detectar push em `production`
- [x] MAJOR/MINOR continuam manuais
- [x] Step de `repository_dispatch` pro `oikos-circular-environment/devops`, `event_type: web-production`, payload `{version, sha}`
- [ ] Criar PAT fine-grained **próprio** (não compartilhado com o do `api`), escopado só pro repo `devops` (feito pelo usuário)
- [ ] Cadastrar o PAT como secret `DEVOPS_DISPATCH_PAT` no repo `web` (usuário cadastra o valor)
- [ ] Validar workflow rodando de verdade num PR de teste

## Definição de Pronto

Um PR de teste, ao ser mergeado em `production`, cria a tag SemVer sozinho e dispara o `repository_dispatch` visível na aba Actions do `devops`.
