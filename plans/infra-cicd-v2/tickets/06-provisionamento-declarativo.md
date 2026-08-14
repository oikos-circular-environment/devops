# T06 — Provisionamento 100% declarativo

**Status**: não iniciada.
**Repositório**: `devops`
**Bloqueia**: [T07](./07-teardown-rebuild.md)

## Escopo

Fechar a causa raiz da [devops#76](https://github.com/oikos-circular-environment/devops/issues/76): nada que a aplicação precise pode depender de memória humana. Hoje `infra/terraform/compute/cloud-init/init.yaml.tftpl` só instala `docker.io`/`docker-compose-v2`, cria o usuário `deploy`, aplica hardening de SSH e configura swap. Tudo o mais era passo manual — e sumiu no redeploy da VM.

## Fora de escopo

Instalar a OCI CLI. Com o backup fora do caminho de deploy ([T02](./02-remover-backup-do-deploy.md)), ela deixa de ser pré-requisito — o problema que originou tudo isso desaparece em vez de ser remendado.

## Levantamento do que hoje é manual

- Units systemd em `docker/systemd/` são copiadas para `/opt/oikos/docker/systemd/` pelo `scp` do deploy, mas **nunca** registradas em `/etc/systemd/system` nem habilitadas. Confirmado na VM: `systemctl list-unit-files 'oikos*'` retorna vazio.
- `oikos-web-restart.{service,timer}` segura o vazamento de memória do Next.js e também não está no ar desde o redeploy.
- `oikos-backup.*` sai de cena em T02.

## Checklist

- [ ] Inventariar, na VM atual, tudo que existe fora do que o cloud-init cria (comparar `/opt/oikos` e `/etc/systemd/system` contra o que está versionado)
- [ ] Registrar e habilitar `oikos-web-restart.{service,timer}` via cloud-init (`write_files` + `runcmd` com `systemctl enable --now`)
- [ ] Conferir se o swap está mesmo aplicado — a VM atual reporta `Swap: 0`, apesar do bloco condicional no `runcmd`
- [ ] Criar `/opt/oikos` com dono/permissão corretos no cloud-init, em vez de depender do `mkdir -p` do primeiro deploy
- [ ] Documentar em `docs/docker-infra.md` a regra: o que não está no Terraform/cloud-init não existe
- [ ] Validar num `apply` de VM descartável antes de [T07](./07-teardown-rebuild.md)

## Definição de Pronto

Uma VM recém-criada pelo Terraform, sem nenhum comando manual, aceita um deploy e sobe a stack completa — incluindo os timers systemd habilitados.

## Registro de execução

_(preencher durante a execução)_
