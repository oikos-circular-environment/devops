# T12 — `devops`: Deploy pipeline — reconciliação de stack independente do dispatcher

**Status**: Implementada, aguardando validação real (o próprio merge desta mudança em `production` é o teste de ponta a ponta — o `deploy.yml` mudou, então o trigger novo precisa disparar o `stack-production` sozinho, coisa que o trigger antigo não faria).
**Repositório**: `oikos-circular-environment/devops`

## Escopo

Eliminar a dependência do `devops` em relação ao `repository_dispatch` do `api`/`web`. Motivação direta (2026-07-03): a PR #34 (modularização do T9) foi mergeada em `production` e **nenhum workflow rodou** — o path-filter restrito do `infra-production` (T11) não cobria `.github/**`, e o resto do repo ficava refém de release do `api`/`web` pra qualquer atualização chegar na VM. Além disso, o `workflow_dispatch` manual exigia preencher SHA e versão à mão ("penoso", nas palavras do usuário).

- **Trigger `push` ampliado**: de `paths:` restrito pra `paths-ignore:` (`plans/**`, `docs/**`, `**/*.md`, `infra/terraform/**`). Qualquer merge em `production` que toque algo executável dispara a reconciliação completa.
- **`infra-production` → `stack-production`**: além do sync de arquivos e dos serviços de infra (T11), o job agora resolve a **última tag SemVer publicada** dos repos `api`/`web` (via `gh api .../tags` + `sort -V`, com `SOURCE_REPO_PAT`), atualiza `API_VERSION`/`WEB_VERSION` no `.env.prod` remoto e faz `pull`/`up -d` dos dois. Backup do Postgres + `prisma migrate deploy` rodam **condicionalmente**, só quando a versão resolvida do `api` difere da pinada (`api_changed`).
- **`workflow_dispatch` simplificado**: `sha`/`version` viraram opcionais — vazios, o build job resolve a última tag e o commit dela sozinho (com dereferência de tag anotada). Nova opção `service: stack` roda só o `stack-production`, com zero inputs — o botão de reconvergência manual (ex.: depois de aprovar um `apply` do Terraform no TFC).

## Fora de escopo

- Bootstrap do zero (infra nova sem nenhuma imagem `api`/`web` no GHCR): o step de `pull` falha — **edge case aceito explicitamente** (decisão de 2026-07-03). O step de convergência de `api`/`web` é separado dos demais de propósito, pra essa falha ficar isolada e visível sem mascarar o resto da reconciliação.
- Disparar a stack em merges que só tocam `infra/terraform/**` — decisão consciente: no momento do push o `apply` nem aconteceu ainda (TFC espera aprovação manual), então rodar a stack aí reconciliaria contra a infra antiga. O caminho pós-apply é o `workflow_dispatch service=stack`.
- Mudar o fluxo de release do `api`/`web` (`repository_dispatch` continua igual, como caminho rápido).

## Decisões

- **"Última tag SemVer publicada" ≠ tag `:latest` do Docker.** A decisão anti-`:latest` (T9/T11) segue de pé: `:latest` é um ponteiro móvel de imagem, sem garantia de ter passado pelo pipeline. Aqui a resolução é determinística via API do GitHub — a tag SemVer mais alta é, por construção do CI, a última release real buildada e publicada. O `.env.prod` continua sendo o registro do que está rodando; a diferença é que agora ele converge pra release mais recente a cada reconciliação, cobrindo inclusive dispatch perdido (webhook do GitHub já falhou 2x neste projeto, com o TFC).
- **`sort -V` na resolução de tags** — a ordem de retorno da API de tags do GitHub não é garantida; ordenação SemVer explícita é a única forma confiável.
- **Backup+migration condicionais ao `api_changed`** — mesma proteção do fluxo de release normal, sem custo quando a versão não muda (caso típico de merge só de infra).

## Referências de spec

- `tickets/09-deploy-pipeline.md` (modularização, decisão anti-`:latest`)
- `tickets/11-deploy-pipeline-infra-only.md` (job que este evolui)
- `.github/workflows/deploy.yml` (job `stack-production`, steps de resolução nos builds)

## Dependências

T9, T11.

## Checklist

- [x] Trigger `push` com `paths-ignore` (docs/planos/terraform fora, todo o resto dispara)
- [x] Job renomeado pra `stack-production`, com `if` cobrindo `push` e `workflow_dispatch service=stack`
- [x] Resolução da última tag SemVer de `api`/`web` via API (`SOURCE_REPO_PAT`, `sort -V`), com output `api_changed`
- [x] Atualização de `API_VERSION`/`WEB_VERSION` no `.env.prod` remoto (só as linhas de versão, nunca os secrets; guard pra repo ainda sem tag)
- [x] Backup + migration condicionais ao `api_changed`
- [x] `pull`/`up -d` de `api`/`web` em step isolado (falha de bootstrap não mascara o resto)
- [x] `workflow_dispatch`: `sha`/`version` opcionais com auto-resolução (inclusive dereferência de tag anotada) e opção `service: stack`
- [ ] Validar de ponta a ponta: merge desta mudança em `production` dispara `stack-production` sozinho, resolve as versões atuais (`api_changed=false` → backup/migrate pulados), converge containers e os 3 hostnames seguem respondendo 200

## Definição de Pronto

Um merge em `production` do `devops` que não toque em `api`/`web` (ex.: só o `deploy.yml`) dispara o `stack-production` sozinho e converge a stack inteira — infra, `api` e `web` na última release publicada — sem nenhum `repository_dispatch` envolvido. O `workflow_dispatch` roda com um clique, sem preencher SHA/versão.
