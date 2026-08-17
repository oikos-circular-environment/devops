# T06 — Provisionamento 100% declarativo

**Status**: **concluída** em 2026-08-14 (validação final no rebuild, [T07](./07-teardown-rebuild.md)).
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

- [x] Inventariado na VM — dois passos manuais escondidos encontrados, ver registro
- [x] Units reconciliadas pelo pipeline (não pelo cloud-init — decisão no registro), via `scripts/reconcile-systemd.sh` (removido no [T09](./09-revisar-scripts-e-systemd.md) em 2026-08-17, junto com a última unit gerida por ele — ver nota no registro de execução)
- [x] Swap conferido: `swap_size_gb = 0` para a `A1.Flex` em `infra/terraform/compute/main.tf` é **deliberado** (12GB de RAM, 1.3GB em uso). Não é bug. A `E2.1.Micro` recebe 9GB.
- [x] `/opt/oikos` e subdiretórios criados pelo cloud-init com dono `deploy`
- [x] Documentado em `docs/docker-infra.md` §7 (seção nova "Provisionamento Declarativo da VM")
- [ ] Validar num `apply` de VM descartável antes de [T07](./07-teardown-rebuild.md)

## Definição de Pronto

Uma VM recém-criada pelo Terraform, sem nenhum comando manual, aceita um deploy e sobe a stack completa — incluindo os timers systemd habilitados.

## Registro de execução

**2026-08-14** — Dois passos manuais escondidos encontrados, ambos confirmados por SSH na VM. Nenhum dos dois estava no inventário original do ticket:

**1. `/opt` é root-owned e o usuário `deploy` não consegue criar nada lá.**

```
drwxr-xr-x 5 root   root   /opt
drwxr-xr-x 6 deploy deploy /opt/oikos
$ mkdir -p /opt/teste-permissao
mkdir: cannot create directory: Permission denied
```

O `/opt/oikos` só existe (com dono `deploy`, timestamp batendo com o redeploy da VM) porque alguém rodou `mkdir` com `sudo` no bootstrap. **Numa VM nova o primeiro deploy morreria** no `mkdir -p /opt/oikos/docker/certs` da `sync-deploy-files`. O `cloud-init` passou a criar a árvore inteira (`docker/certs`, `nginx`, `observability`, `scripts`) com `chown deploy:deploy`, mais os três fragmentos de env já com permissão `600`.

**2. Units systemd copiadas mas nunca registradas.** O deploy copiava `docker/systemd/` para `/opt/oikos/docker/systemd/`, e ninguém instalava em `/etc/systemd/system`. Por isso o `oikos-web-restart.timer` sumiu no redeploy sem ninguém notar.

**Decisão de desenho — reconciliação pelo pipeline, não pelo cloud-init.** O ticket previa `write_files` no cloud-init, o que duplicaria o conteúdo das units entre o repo e o template Terraform, e exigiria `terraform apply` (recriação de VM) para editar um timer. Em vez disso, `scripts/reconcile-systemd.sh` roda a cada deploy: instala o que está versionado e **desabilita/remove** qualquer unit `oikos-*` que não exista mais no repo. O repo segue fonte única da verdade, e como o deploy roda depois de todo rebuild, a convergência é automática.

**Achado durante o teste do mecanismo na VM real**: `scp -r` não apaga arquivo removido do repo. O `oikos-backup.timer` — deletado no [T02](./02-remover-backup-do-deploy.md) — ainda estava em `/opt/oikos/docker/systemd/` e foi **reabilitado** no primeiro teste de instalação, apontando para um `backup-postgres.sh` que não existe mais (falharia toda madrugada, em silêncio). Foi exatamente o cenário que motivou trocar "copiar" por "reconciliar". Confirmado depois:

```
Unit removida (nao existe mais no repo): oikos-backup.service
Unit removida (nao existe mais no repo): oikos-backup.timer
```

Estado final na VM: só `oikos-web-restart.timer` habilitado, próxima execução 03:00 UTC. O diretório de staging também passou a ser limpo antes do `scp`.

**Nota (2026-08-17, [T09](./09-revisar-scripts-e-systemd.md))**: `oikos-web-restart.*` foi removido (mitigação de leak sem fix confirmado, decidiu-se monitorar por Grafana em vez de restart cego) e não sobrou nenhuma unit gerida pelo repo — `oikos-backup.*` já tinha saído no T02. Sem unit nenhuma pra reconciliar, `scripts/reconcile-systemd.sh`, `docker/systemd/` e a criação de `/opt/oikos/scripts` no cloud-init foram removidos junto. O mecanismo de reconciliação descrito acima continua válido como referência, caso surja necessidade real de gerir unit systemd de novo.

`oikos-web-restart.service` ganhou os três `--env-file`, acompanhando a fragmentação do [T05](./05-fragmentar-envs.md) — sem isso o restart noturno rodaria sem as variáveis.

**Validações**: `terraform validate` Success, `terraform fmt -check -recursive` limpo, `actionlint` exit 0, `bash -n` no script novo, e o template do cloud-init parseando como YAML válido.

**Quarto passo manual, achado ao responder "o rebuild derruba a observabilidade também?" (2026-08-14)**

Sim: `module.compute.oci_core_instance.observability` também está em `must be replaced` no plan, porque as duas VMs compartilham o mesmo `init.yaml.tftpl`. E a `E2.1.Micro` tinha o mesmo tipo de buraco da `A1.Flex`:

`observability/.env.observability` (que carrega `GF_ADMIN_USER`/`GF_ADMIN_PASSWORD` do Grafana) é **gitignored e não era renderizado por workflow nenhum**. Na VM, o arquivo tinha timestamp `Jul 23 02:10` — do bootstrap — enquanto os arquivos sincronizados pelo CI eram de `Aug 14 16:13`. Nunca tinha sido tocado desde a criação manual.

Pior que sumir: o `env_file` está declarado com `required: false`, então numa VM nova o compose **não falharia** — o Grafana subiria com `GF_SECURITY_ADMIN_USER`/`GF_SECURITY_ADMIN_PASSWORD` vazios, em silêncio, com `GF_AUTH_ANONYMOUS_ENABLED=true` e role `Admin`.

Corrigido no mesmo padrão dos outros fragmentos: `deploy-stack.yml` renderiza o `.env.observability` no runner a partir de `secrets.GF_ADMIN_PASSWORD` + `vars.GF_ADMIN_USER` (Environment `infra-production`), copia junto do `scp -r observability` e apaga do runner em seguida. Os valores atuais foram lidos da VM e cadastrados no Environment.

**O que o rebuild da E2.1.Micro leva junto, e não volta**: os volumes `prometheus_data`, `loki_data`, `tempo_data` e `grafana_data` — histórico de métricas, logs e traces. Dashboards e datasources voltam, porque vêm de `grafana/provisioning` e `grafana/dashboards`, versionados no repo. Perda aceita (dado de telemetria, projeto em MVP), mas registrada para não virar surpresa.
