# T03 — Extrair composite actions

**Status**: não iniciada.
**Repositório**: `devops`
**Bloqueia**: [T04](./04-quebrar-deploy-yml.md)

## Escopo

Tirar a duplicação de `.github/workflows/deploy.yml` **sem ainda quebrar o arquivo**. Passo deliberadamente conservador: zero mudança de comportamento, reversível, e valida as actions antes de a estrutura mudar.

Duplicações medidas hoje: setup de chave SSH **7×** idêntico, `scp` de arquivos de deploy **3×**, resolução de tag/SHA **2×** (`api-build` e `web-build`, diferindo só no nome do repo).

## Fora de escopo

Quebrar o `deploy.yml` em vários arquivos (é [T04](./04-quebrar-deploy-yml.md)). Mudar o que os passos fazem.

## Armadilhas

- Composite action **não** enxerga `secrets.*` nem `vars.*` do caller — tudo tem que entrar como `inputs`.
- `uses: ./...` exige `actions/checkout` antes, porque o path é relativo ao `$GITHUB_WORKSPACE`. Hoje `api-migrate`, `api-deploy-container` e `web-deploy-container` **não fazem checkout nenhum** e vão ganhar esse step.

## Checklist

- [ ] `.github/actions/ssh-setup/action.yml` — inputs `ssh-private-key` e `vm-host`; substitui as 7 duplicações
- [ ] `.github/actions/resolve-release/action.yml` — inputs `repo`, `version`, `sha`, `github-token`; outputs `tag` e `sha`; preserva a dereferência de tag anotada (`TYPE == "tag"`) e o `sort -V`
- [ ] `.github/actions/sync-deploy-files/action.yml` — o `scp` de `docker nginx observability scripts` + o `sed` do `__OBS_VM_PRIVATE_IP__`
- [ ] Adicionar `actions/checkout@v7` nos 3 jobs que hoje não fazem checkout
- [ ] Substituir as ocorrências no `deploy.yml` monolítico
- [ ] Validar com `workflow_dispatch` manual (`service=stack`, que não rebuilda imagem) antes de qualquer release real

## Definição de Pronto

`deploy.yml` sem nenhum bloco de SSH/scp/resolução de versão duplicado, e um `workflow_dispatch` completo rodando com o mesmo resultado de antes.

## Registro de execução

- Criadas as 3 composite actions em `.github/actions/`.
- `deploy.yml` atualizado para usar as actions; logica extra do `api-sync` (preservar `WEB_VERSION` e copiar `.env.prod` renderizado) mantida inline.
- `stack-production` manteve o `scp` inline por ser diferente (nao copia pasta `docker` inteira).
- Adicionado `actions/checkout@v7` nos jobs `api-migrate`, `api-deploy-container` e `web-deploy-container`.
- Sintaxe YAML validada com sucesso.
