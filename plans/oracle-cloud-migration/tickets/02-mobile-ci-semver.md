# T2 — `mobile`: CI + Versionamento

**Status**: Em andamento (`ci.yml` escrito, falta validar rodando)
**Repositório**: `oikos-circular-environment/mobile`

## Escopo

CI do repo (format → lint → test) e tag SemVer automática em `production`. Igual ao `api`/`web` no padrão de CI, mas sem nenhuma integração com o `devops`.

## Fora de escopo

Qualquer disparo de `repository_dispatch` ou integração com o `devops` — o artefato do `mobile` vai pras lojas (EAS/App Store/Play Store), não pra infraestrutura própria. Fora do escopo de deploy deste épico.

## Referências de spec

- `00-epic-brief.md` §Escopo por Repositório, §Versionamento e Fluxo de Release

## Dependências

Nenhuma — totalmente independente do resto do épico, pode rodar em paralelo com qualquer outra ticket.

## Checklist

- [x] Criar `.github/workflows/ci.yml` com jobs `format → lint → test` (`npx biome ci .` + `npm test`)
- [x] Job só falha o merge se algum desses passos falhar
- [x] Step de tag SemVer automática (`mathieudutour/github-tag-action`, `default_bump: patch`) ao detectar push em `production`
- [x] MAJOR/MINOR continuam manuais
- [x] Confirmado: **nenhum** step de `repository_dispatch` ou referência ao `devops`
- [ ] Validar workflow rodando de verdade num PR de teste

## Definição de Pronto

Um PR de teste, ao ser mergeado em `production`, cria a tag SemVer sozinho. Nenhuma ação além disso é disparada.
