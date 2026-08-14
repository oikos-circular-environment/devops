# T08 — Padronizar CI de `api` e `web`

**Status**: não iniciada.
**Repositórios**: `api`, `web`
**Independente** — pode correr em paralelo aos demais.

## Escopo

Mesmo gate mínimo rodando **antes** do merge nos dois repos. `mobile` fica de fora: tem EAS Workflow e contexto de release próprios.

## Gate mínimo comum

`checkout` → `setup-node@24` (cache npm) → `npm ci` → `biome ci .` → **suíte de testes de verdade**, em PR para `development` e para `production`.

## Achado que muda o escopo (verificado 2026-08-14)

A premissa inicial — "o `web` não tem test runner, então precisa de Vitest + RTL" — está **parcialmente errada**. O que existe de fato:

- O `web` **tem** suíte de testes: 6 specs Playwright em `web/e2e/` (`login`, `layout`, `suporte`, `verify-email`, `header-account-button`, `sidebar-moderation-visibility`), com `fake-api-server.mjs` e `webServer` já configurado no `playwright.config.ts`. Script `test:e2e` existe no `package.json`.
- **Nada disso roda no CI.** O `web/.github/workflows/ci.yml` tem só `quality` (biome + `next build`), `lighthouse`, `tag` e `notify-devops`. Nenhum job chama `test:e2e`.

Ou seja: o problema não é ausência de testes, é **teste escrito que ninguém executa**. O ganho maior e mais barato é ligar o que já existe, não escrever suíte nova.

Ordem de valor:

1. **Rodar o `test:e2e` que já existe no CI** — custo quase zero, cobre login, layout e formulários. É isso que fecha o gate de verdade.
2. Vitest + RTL para lógica de unidade — investimento maior, fica para depois de (1), e só se a lacuna remanescente justificar.

O TODO em `web/.github/workflows/ci.yml` que diz "nenhum test runner configurado no repo ainda" está desatualizado e sai junto.

## O que continua específico

- `api`: jobs `integration` e `e2e` (precisam de infra viva via `test:infra:up`)
- `web`: Lighthouse restrito a PR → `production` (já ajustado em web#42)

## Decisão

**Não** extrair `tag` + `notify-devops` para um reusable workflow cross-repo hospedado no `devops`. São ~30 linhas estáveis e quase idênticas; a indireção cross-repo traz pin de branch/versão e permissão de PAT que não se pagam nesse tamanho de duplicação. Reavaliar só se esse bloco crescer ou divergir.

## Checklist

- [ ] `web/.github/workflows/ci.yml`: job `e2e` rodando `npm run test:e2e` (Playwright), com `needs: quality` — espelhando o shape do `api`
- [ ] Remover o TODO desatualizado de `web/.github/workflows/ci.yml`
- [ ] Alinhar o shape do job `quality` entre os dois repos (mesma ordem de steps, mesmo `setup-node`, mesmo cache)
- [ ] Conferir que o gate roda em PR para `development` **e** para `production` nos dois
- [ ] Avaliar (não necessariamente fazer agora) se falta cobertura de unidade que justifique Vitest + RTL

## Nota sobre branch

`api` e `web` são repositórios separados — não cabem na branch `77-plano-infra-cicd-v2` do `devops`. Cada um precisa da sua branch, referenciando a issue por `oikos-circular-environment/devops#77`.

## Definição de Pronto

Um PR com erro de lint ou teste quebrado é barrado antes do merge, igual nos dois repos, sem depender de o autor lembrar de rodar nada localmente.

## Registro de execução

_(preencher durante a execução)_
