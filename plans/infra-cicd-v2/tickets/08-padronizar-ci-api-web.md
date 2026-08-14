# T08 — Padronizar CI de `api` e `web`

**Status**: não iniciada.
**Repositórios**: `api`, `web`
**Independente** — pode correr em paralelo aos demais.

## Escopo

Mesmo gate mínimo rodando **antes** do merge nos dois repos. `mobile` fica de fora: tem EAS Workflow e contexto de release próprios.

## Gate mínimo comum

`checkout` → `setup-node@24` (cache npm) → `npm ci` → `biome ci .` → **suíte de testes de verdade**, em PR para `development` e para `production`.

## Achado que muda o escopo

O `web` **não tem test runner configurado**. O job `quality` roda `biome` + `npm run build`, usando o build como proxy de teste (há TODO explícito em `web/.github/workflows/ci.yml`). Padronizar sem resolver isso deixa o gate de fachada — o `web` não tem cobertura de lógica nenhuma barrando merge.

Por isso adicionar Vitest + RTL no `web` faz parte deste ticket, não de um futuro.

## O que continua específico

- `api`: jobs `integration` e `e2e` (precisam de infra viva via `test:infra:up`)
- `web`: Lighthouse restrito a PR → `production` (já ajustado em web#42)

## Decisão

**Não** extrair `tag` + `notify-devops` para um reusable workflow cross-repo hospedado no `devops`. São ~30 linhas estáveis e quase idênticas; a indireção cross-repo traz pin de branch/versão e permissão de PAT que não se pagam nesse tamanho de duplicação. Reavaliar só se esse bloco crescer ou divergir.

## Checklist

- [ ] Adicionar Vitest + RTL no `web` com pelo menos a cobertura da lógica que hoje não tem nenhuma
- [ ] `web/.github/workflows/ci.yml`: job `quality` passa a rodar testes de verdade, não `build` como proxy
- [ ] Alinhar o shape do job `quality` entre os dois repos (mesma ordem de steps, mesmo `setup-node`, mesmo cache)
- [ ] Conferir que o gate roda em PR para `development` **e** para `production` nos dois
- [ ] Remover o TODO de `web/.github/workflows/ci.yml`

## Definição de Pronto

Um PR com erro de lint ou teste quebrado é barrado antes do merge, igual nos dois repos, sem depender de o autor lembrar de rodar nada localmente.

## Registro de execução

_(preencher durante a execução)_
