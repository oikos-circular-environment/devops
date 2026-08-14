# T04 — Quebrar o `deploy.yml` em entrypoints

**Status**: não iniciada.
**Repositório**: `devops`
**Depende de**: [T03](./03-composite-actions.md) · **Bloqueia**: [T05](./05-fragmentar-envs.md)

## Escopo

458 linhas e 9 jobs num arquivo só, servindo 3 gatilhos diferentes. Separar por serviço, um entrypoint por gatilho.

## Estrutura alvo

```
.github/workflows/
  deploy-api.yml         # repository_dispatch[api-production] + workflow_dispatch
  deploy-web.yml         # repository_dispatch[web-production] + workflow_dispatch
  deploy-stack.yml       # push[production] (paths-ignore) + workflow_dispatch
  _build-push-image.yml  # workflow_call — build+push, idêntico entre api e web
```

## Decisões

- **Só o build vira `workflow_call`.** Os pipelines de deploy continuam com jobs próprios em cada entrypoint: `environment:` não é herdado pelo callee, e a indireção não paga o custo quando cada entrypoint já serve um único serviço.
- **`secrets` explícitos em `_build-push-image.yml`**, nunca `secrets: inherit` — `inherit` repassa todo o contexto do caller, incluindo secrets de app, para um job que só precisa de `GHCR_PAT` e `SOURCE_REPO_PAT`.
- **`concurrency: group: deploy-vm` é escopado no repositório**, não no arquivo. Basta repetir o bloco nos 3 entrypoints para manter a serialização de hoje — os três mexem nos mesmos arquivos e containers da mesma VM.

## Armadilhas

- Reusable workflow local tem que ficar direto em `.github/workflows/`, sem subpasta.
- Limite de aninhamento de `workflow_call` é 4 níveis; a profundidade aqui é 2.
- `deploy.yml` roda a partir do branch default (`production`) — a quebra precisa estar mergeada lá **antes** da próxima release de `api`/`web`, senão o `repository_dispatch` chega e não acha o workflow. Mesma regra já documentada em `docs/docker-infra.md#1`, agora valendo para 3 arquivos.

## Checklist

- [ ] Criar `_build-push-image.yml` com inputs `service`/`dockerfile`/`image`/`build-args` e output `version`
- [ ] Criar `deploy-api.yml` (build → sync → migrate → deploy-container; sem backup, já removido em T02)
- [ ] Criar `deploy-web.yml` (build → sync → deploy-container)
- [ ] Criar `deploy-stack.yml` (reconciliação completa, incluindo o step de observabilidade via bastion)
- [ ] Repetir `concurrency: group: deploy-vm` nos 3 entrypoints
- [ ] Remover o `deploy.yml` antigo
- [ ] Validar cada entrypoint por `workflow_dispatch` manual antes de deixar release real depender
- [ ] Atualizar `docs/docker-infra.md#1` com a estrutura nova

## Definição de Pronto

Os 3 entrypoints rodam isoladamente por `workflow_dispatch`, o `repository_dispatch` de `api` e de `web` chega no arquivo certo, e dois deploys concorrentes continuam serializados pelo grupo `deploy-vm`.

## Registro de execução

_(preencher durante a execução)_
