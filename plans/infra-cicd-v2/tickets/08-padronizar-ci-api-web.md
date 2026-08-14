# T08 — Padronizar CI de `api` e `web`

**Status**: **bloqueada** por [web#51](https://github.com/oikos-circular-environment/web/issues/51).
**Repositórios**: `api`, `web`
**Independente** dos demais tickets deste plano.

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

## Registro de execução

**2026-08-14** — Suíte e2e do `web` executada localmente pela primeira vez (`CI=1 npx playwright test`, após `npm ci` — o `node_modules` local estava sem o `zustand` que veio no web#50).

Resultado: **81 passaram, 6 falharam**. As 6 falhas são todas de `e2e/header-account-button.spec.ts` (2 casos × 3 viewports), e são falhas **legítimas**:

> `src/components/account-menu-button.tsx` foi criado no web#50 junto com esses testes, mas **nunca foi importado nem renderizado**. `grep -rn "AccountMenuButton" src/` bate só na própria definição. O `site-header.tsx` renderiza logo, `NavigationMenu`, `ModeToggle` e `SiteHeaderMobileNav` — sem botão de conta. Na prática, o header em `development` está sem Entrar, sem Registrar e sem acesso ao dashboard.

Isso é a justificativa do ticket se provando na prática: o teste existia, estava certo, e apontava um bug real que ninguém via porque o CI nunca o executava.

Aberta [web#51](https://github.com/oikos-circular-environment/web/issues/51) com o diagnóstico. **O job `e2e` no `ci.yml` só entra depois desse fix** — ligar um gate vermelho travaria todo merge no repo. A branch local com o `ci.yml` alterado foi descartada; o conteúdo do job está preservado no corpo da issue e no checklist acima.

Também confirmado: os 3 projects do `playwright.config.ts` (mobile/tablet/desktop) são todos Chromium, então `npx playwright install --with-deps chromium` cobre a suíte inteira no runner.
