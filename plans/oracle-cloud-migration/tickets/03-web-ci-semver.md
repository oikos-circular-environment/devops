# T3 — `web`: CI + Versionamento

**Status**: **Pronta.** Pipeline de deploy automático validado de ponta a ponta em 2026-07-03 — merge real em `production` disparou tag SemVer + `repository_dispatch` + deploy sozinho, sem intervenção manual (`web` rodando `v0.0.3` em produção).
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
- [x] Step de `repository_dispatch` pro `oikos-circular-environment/devops`, `event_type: web-production`, payload `{version, sha}` — [PR #13](https://github.com/oikos-circular-environment/web/pull/13) adiciona `-f`/`--fail` no `curl`; sem isso, uma resposta HTTP de erro do GitHub (ex: 401 por secret ausente) não falhava o step, mascarando o problema
- [x] Criar PAT fine-grained **próprio** (não compartilhado com o do `api`), escopado só pro repo `devops`, `Contents: Read and write` — na primeira tentativa errou o repositório selecionado (apontou pro `web` em vez do `devops`) e depois a permissão (`Read-only`); corrigido recriando o token do zero
- [x] Cadastrar o PAT como secret `DEVOPS_DISPATCH_PAT` no repo `web`
- [x] Validar workflow rodando de verdade num PR de teste — merge real em `production` (2026-07-03) disparou `repository_dispatch` sozinho, `devops` buildou e implantou `v0.0.3` automaticamente, sem `workflow_dispatch` manual

## Definição de Pronto

Um PR de teste, ao ser mergeado em `production`, cria a tag SemVer sozinho e dispara o `repository_dispatch` visível na aba Actions do `devops`.

## Guia: criar o PAT fine-grained

Mesmo procedimento do T1 (`api`) — ver o guia completo lá. Resumo:
1. GitHub → avatar → **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens** → **Generate new token**
2. **Resource owner**: `oikos-circular-environment` · **Repository access**: só **`devops`** · **Permissions** → **Contents**: `Read and write`
3. **Generate token**, copiar o valor (aprovar em **Pending requests** da organização se necessário)
4. Cadastrar via CLI: `gh secret set DEVOPS_DISPATCH_PAT --repo oikos-circular-environment/web` (ou pela UI: repo **`web`** → **Settings** → **Secrets and variables** → **Actions** → **New repository secret** → nome `DEVOPS_DISPATCH_PAT` → colar)

**Token separado do `api`** — não reaproveitar o mesmo, mesmo com permissão idêntica.
