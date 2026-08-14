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

- [x] ~~Criar `_build-push-image.yml`~~ — criado e depois **descartado**, ver decisão no registro
- [x] Criar `deploy-api.yml` (build → sync → migrate → deploy-container; sem backup, já removido em T02)
- [x] Criar `deploy-web.yml` (build → sync → deploy-container)
- [x] Criar `deploy-stack.yml` (reconciliação completa, incluindo o step de observabilidade via bastion)
- [x] Repetir `concurrency: group: deploy-vm` nos 3 entrypoints
- [x] Remover o `deploy.yml` antigo
- [ ] Validar cada entrypoint por `workflow_dispatch` manual antes de deixar release real depender (pendente — precisa dos 4 arquivos mergeados em `production`, não dá pra rodar a partir desta branch)
- [x] Atualizar `docs/docker-infra.md#1` com a estrutura nova

## Definição de Pronto

Os 3 entrypoints rodam isoladamente por `workflow_dispatch`, o `repository_dispatch` de `api` e de `web` chega no arquivo certo, e dois deploys concorrentes continuam serializados pelo grupo `deploy-vm`.

## Registro de execução

**Estrutura criada**: `_build-push-image.yml` (`workflow_call`, job `build`), `deploy-api.yml` (`build`→`sync`→`migrate`→`deploy-container`), `deploy-web.yml` (`build`→`sync`→`deploy-container`), `deploy-stack.yml` (`stack-production`). `deploy.yml` removido. Todos os `if:` de roteamento por evento sumiram — cada arquivo só serve o gatilho do seu próprio `on:`. O `workflow_dispatch` antigo (`inputs.service` choice `api|web|stack`) não existe mais; `deploy-api.yml`/`deploy-web.yml` ganharam `workflow_dispatch` com `inputs.sha`/`inputs.version`, `deploy-stack.yml` ganhou `workflow_dispatch: {}` sem inputs.

**Decisão: `web` NÃO usa o `_build-push-image.yml` reusável — builda em job próprio dentro de `deploy-web.yml`.** Investiguei a sugestão do ticket original (input opcional `environment` no reusable, `environment: ${{ inputs.environment }}` no job, default `""` pra rotear o `api` sem Environment nenhum) e descartei por dois motivos, confirmados na doc oficial ("Supported keywords for jobs that call a reusable workflow", docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations):

1. `environment:` **não é keyword suportado** no job caller (o job que só tem `uses:` apontando pro reusable) — só `name`/`uses`/`with`/`secrets`/`strategy`/`needs`/`if`/`concurrency`/`permissions`. Isso significa que o job de `deploy-web.yml` que chamaria o reusable não consegue ler `${{ vars.NEXT_PUBLIC_API_URL }}`/`${{ secrets.NEXT_PUBLIC_CLIENT_API_KEY }}` do Environment `web-production` pra montar o `build-args` e repassar como input — essas leituras só resolvem contra o Environment dentro de um job que declara `environment:` diretamente nele.
2. A alternativa seria mover `environment: ${{ inputs.environment }}` pro job **dentro** do próprio `_build-push-image.yml` (aí sim o job roda com o Environment certo e `vars`/`secrets` resolvem). Isso funcionaria pro propósito de "ligar/desligar" o Environment, mas força o arquivo genérico (usado por `api` e `web`) a conhecer os nomes de build-arg específicos do `web` (`NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_CLIENT_API_KEY`) hardcoded no step de build — o input genérico `build-args` (string livre) não resolve isso, porque quem montaria essa string é o caller, e o caller (por (1)) não tem acesso aos valores do Environment pra montá-la.

Não achei confirmação definitiva na doc sobre o comportamento de `environment: ${{ inputs.x }}` avaliando pra string vazia (alguns relatos de comunidade sugerem que funciona como "sem Environment", mas não é documentado formalmente) — dado que isso é pipeline de produção, não valia o risco de um comportamento não documentado só pra economizar a duplicação de ~6 steps. Segui a saída de escape que o ticket já previa: `deploy-web.yml` tem os mesmos 6 steps de build do `api` (checkout devops → `resolve-release` → checkout `web` → Buildx → login GHCR → `build-push-action`), com `environment: web-production` no job, exatamente como já era antes da quebra. `_build-push-image.yml` ficou genérico (inputs `service`/`source-repo`/`dockerfile`/`image`/`version`/`sha`/`build-args`, secrets `GHCR_PAT`/`SOURCE_REPO_PAT` explícitos, output `version`) e hoje só tem um consumidor (`deploy-api.yml`) — mas segue pronto pra um segundo consumidor se essa restrição de Environment for resolvida depois (ex.: se `NEXT_PUBLIC_API_URL`/`NEXT_PUBLIC_CLIENT_API_KEY` deixarem de ser Environment-scoped).

Documentei essa decisão em `docs/docker-infra.md#1` (bullets "`_build-push-image.yml`" e "`web` builda num job próprio").

**Validação rodada**:
- `python3 -c "import yaml; ..."` nos 4 arquivos → `YAML OK`.
- `grep -rn "inputs.service" .github/workflows/` → só bate em `_build-push-image.yml:70` e `:85`, que são o input próprio do reusable (`inputs.service` = `"api"`/`"web"` passado via `with:`), não o `workflow_dispatch.inputs.service` (choice) antigo, que foi removido. Sem resíduo do input antigo.
- `git status -s` → `D .github/workflows/deploy.yml`, `?? .github/workflows/{_build-push-image,deploy-api,deploy-stack,deploy-web}.yml`, mais `M docs/docker-infra.md`. (`M plans/infra-cicd-v2/tickets/08-padronizar-ci-api-web.md` é mudança pré-existente de outra sessão, não tocada aqui.)
- `actionlint` não está no PATH deste ambiente — não rodou. Fica pendente pra CI ou uma máquina com o binário instalado.

**Em aberto / risco**: o item de validação por `workflow_dispatch` manual do checklist não dá pra fechar a partir desta branch — precisa dos arquivos mergeados em `production` primeiro (mesma restrição já documentada na seção "Armadilhas" do ticket, e em `docs/docker-infra.md#1`: `repository_dispatch` só acha workflow que já existe no branch default). Recomendo rodar isso manualmente logo após o merge, antes da próxima release de `api`/`web` depender do fluxo novo.

**Correção pós-revisão (2026-08-14)**: o `_build-push-image.yml` foi **removido**. A investigação acima está certa e é o que justifica o `web` builder inline — mas a consequência é que o reusable ficou com **um único chamador** (`deploy-api.yml`). Reusable com um consumidor é indireção sem nenhuma deduplicação: paga o custo de um arquivo a mais, de `secrets` declarados nome a nome e de uma camada de `inputs`, sem economizar linha nenhuma. O build do `api` voltou pra dentro de `deploy-api.yml`, igual ao do `web`.

O resultado são 3 arquivos autocontidos (194 + 125 + 113 = 432 linhas contra as 458 do monolito), e a deduplicação real fica nas composite actions do [T03](./03-composite-actions.md) — só o `ssh-setup` já elimina 7 repetições. Se um dia `NEXT_PUBLIC_API_URL`/`NEXT_PUBLIC_CLIENT_API_KEY` deixarem de ser Environment-scoped, aí sim vale reconsiderar o reusable, com dois consumidores de verdade.

**Validação**: `actionlint` v1.7.7 rodado nos 3 arquivos finais — exit 0, sem warning. (O agente não tinha o binário; instalei e rodei depois.) Também conferido por `grep`: zero `if:` de roteamento residual, zero `inputs.service`, `concurrency: group: deploy-vm` presente nos 3, e os `environment:` preservados (`api-production` no sync do api, `web-production` no build e no deploy-container do web).
