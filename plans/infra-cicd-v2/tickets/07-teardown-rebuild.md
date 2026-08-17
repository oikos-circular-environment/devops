# T07 — Teardown e rebuild do zero

**Status**: **concluído em 2026-08-17** — ver "Retomada concluída" abaixo. Único item não feito: restore dos dumps (decisão do usuário, sem dado relevante a preservar).
**Repositório**: `devops`
**Depende de**: [T01](./01-salvaguarda-dados.md) (bloqueante) e [T06](./06-provisionamento-declarativo.md)

## Escopo

Destruir a infra OCI inteira e subir do zero pelo Terraform. **Downtime é aceito explicitamente.** O objetivo não é só limpar drift acumulado — é provar que o provisionamento virou declarativo de verdade ([T06](./06-provisionamento-declarativo.md)).

## Pré-condição inegociável

[T01](./01-salvaguarda-dados.md) concluída **com restore validado**. O `terraform destroy` apaga os boot volumes, e com eles `postgresql_data`, `redis_data` e `minio_data`. Sem dump verificado, não executar.

## Atenção

- **IPs mudam.** `vars.VM_HOST` e `vars.OBSERVABILITY_PRIVATE_IP` no GitHub precisam ser atualizados, senão todo deploy aponta pro vazio. O IP público também está em `docs/infrastructure.md` (hoje `167.126.6.162` / `10.0.1.155` / `10.0.2.51`).
- **DNS**: o módulo `dns` já consome `module.compute.app_public_ip`, então o registro A acompanha o rebuild sozinho. Conferir propagação antes de declarar pronto.
- **Certificado Cloudflare Origin CA**: materializado no deploy a partir dos secrets `CLOUDFLARE_ORIGIN_CERT`/`CLOUDFLARE_ORIGIN_KEY` — não precisa reemitir, mas confirmar que chegou na VM nova.
- **`dns_label` da subnet pública** (`oikossub`) é imutável na OCI; manter o valor.
- Os blocos `import` de `cloudflare_zone_setting` em `infra/terraform/main.tf` podem precisar de atenção num state limpo.

## Checklist

- [x] Confirmar [T01](./01-salvaguarda-dados.md) concluída e restore validado
- [x] Confirmar [T06](./06-provisionamento-declarativo.md) validada em VM descartável
- [x] `terraform destroy` completo
- [x] `terraform apply` do zero
- [x] Atualizar `vars.VM_HOST` e `vars.OBSERVABILITY_PRIVATE_IP` no repo `devops`
- [x] Atualizar IPs em `docs/infrastructure.md`
- [x] Conferir cloud-init concluído sem erro nas duas VMs (`cloud-init status`)
- [x] Deploy `service=stack` para materializar a stack
- [ ] Restaurar os dumps de Postgres, Redis e MinIO — **não feito de propósito**: dado de teste de MVP, sem nada relevante a preservar (decisão do usuário)
- [x] Conferir DNS propagado e TLS válido nos domínios
- [x] Deploy de `api` e de `web` nas últimas tags publicadas

## Definição de Pronto

`https://api.oikos.company/health` e `https://oikos.company` respondendo, dados restaurados conferidos, e **nenhum passo manual** executado na VM em todo o processo. Qualquer comando manual que tenha sido necessário é bug de [T06](./06-provisionamento-declarativo.md) e volta pra lá.

## Registro de execução

**2026-08-14 — teardown**

O workspace `oracle-server` é **VCS-connected**, então `terraform destroy` pela CLI é recusado (`Apply not allowed for workspaces with a VCS connection`). O caminho suportado é a API do Terraform Cloud: `POST /api/v2/runs` com `is-destroy: true`. Run `run-HpCGSSgDTibFXEUS`, **30 recursos destruídos** — as 2 VMs, a rede inteira (VCN, 2 subnets, internet/NAT gateway, 2 route tables, security list), os 5 registros DNS, o certificado Origin CA, ruleset/bot management/Turnstile, os 3 zone settings e o bucket `oikos-backups` com o IAM associado.

### Pré-requisitos da subida (não esquecer)

Dois recursos Cloudflare **mudam de valor ao serem recriados** e invalidam secrets já cadastrados:

1. **`cloudflare_origin_ca_certificate`** — novo par cert/chave. `CLOUDFLARE_ORIGIN_CERT` e `CLOUDFLARE_ORIGIN_KEY` (secrets de repositório) precisam ser reescritos a partir de `terraform output -raw origin_certificate_pem` / `origin_private_key_pem`. Sem isso o nginx sobe com certificado que a Cloudflare não reconhece.
2. **`cloudflare_turnstile_widget`** — nova sitekey e secret. `TURNSTILE_SITE_KEY` (var) e `TURNSTILE_SECRET_KEY` (secret) no Environment `web-production` ficam obsoletos, e o formulário de `/suporte` quebra até serem atualizados.

Mais os já previstos: `VM_HOST` e `OBSERVABILITY_PRIVATE_IP`, e os IPs em `docs/infrastructure.md`.

### Sobre o DNS cair na Squarespace durante a janela

Diagnóstico fechado nesta sessão. A zona é `full` no Cloudflare, a delegação no TLD `.company` aponta corretamente para `todd`/`katja.ns.cloudflare.com`, e **não há registro DS** (DNSSEC desligado no registrar, então não é o caso clássico de DS órfão). O que explica o sintoma é o `original_registrar: squarespace domains ii llc` (herdeira do Google Domains — `original_ns` são `ns-cloud-*.googledomains.com`): enquanto o apex não existir na zona, a resposta é NXDOMAIN e o domínio cai no que o registrar servir.

Consequência prática, registrada para as próximas vezes: **`destroy` apaga `cloudflare_dns_record.apex` e `.www`**, criando exatamente essa janela. Um `apply` sozinho **não** cria — quando só o `user_data` muda, os registros aparecem como `updated in-place` (só o `content` troca de IP) e o `www` nem entra no plano, por ser CNAME para o apex e independente do IP.

**Regra para os próximos rebuilds: rebuild é `apply`, não `destroy` + `apply`.** Alterar o cloud-init já marca as VMs como `must be replaced`, o que recria as instâncias sem nunca remover o DNS. O `destroy` desta vez foi pedido explicitamente para começar do zero.

A zona tem 20 registros e o Terraform gerencia 5 — os outros 15 (MX iCloud, SPF/DKIM/DMARC, Resend, `survey` → Vercel, os `local-*` de cloudflared tunnel) não estão no state e sobreviveram ao teardown.

## Onde parou (2026-08-14, fim do dia)

A infra foi recriada com sucesso (`run-FxVSPiRKdpAodKSb`, 27 recursos + 3 imports). IPs novos: **`157.151.31.135`** (A1.Flex) e **`10.0.2.70`** (E2.1.Micro), já atualizados em `vars.VM_HOST` e `vars.OBSERVABILITY_PRIVATE_IP`, junto com `CLOUDFLARE_ORIGIN_CERT`/`_KEY` e `TURNSTILE_SITE_KEY`/`_SECRET_KEY`, todos lidos dos outputs do Terraform.

**O cloud-init do [T06](./06-provisionamento-declarativo.md) funcionou**: a VM subiu com `/opt/oikos` criado, dono `deploy`, fragmentos de env em `600` e Docker pronto — sem nenhum comando manual.

Dos quatro deploys, só o `deploy-infra` passou. Os outros três falharam e as correções já estão na branch (PR #92), mas **ainda não foram exercitadas de ponta a ponta**.

### Estado atual da infra

- As duas VMs estão de pé, mas com **caminhos envenenados** pelo run que falhou: `/opt/oikos/docker/init-db.sh` e `/opt/oikos/observability/prometheus/prometheus.yml` foram criados pelo Docker como diretórios `root` quando o arquivo do bind-mount não existia. Enquanto estiverem lá, o `scp` volta a falhar.
- O banco na VM tem schema aplicado e dados de teste da validação — **não é o dado restaurado do dump**.
- `oikos.company`, `www`, `api`, `grafana` e `minio` **não resolvem**: os registros foram destruídos no teardown e recriados apontando para o IP novo, mas sem aplicação servindo.

### Retomada — nesta ordem

1. **Merge da PR #92** em `development` e depois `development` → `production`. Os workflows rodam a partir de `production`; sem isso o CI corrigido não existe lá. A PR irmã `api#89` pode ser mergeada em paralelo (não bloqueia a infra).
2. **Recriar as duas instâncias** via Terraform com `replace-addrs` — não `destroy`. Limpa os caminhos envenenados e valida o pipeline corrigido a partir de VM limpa, sem apagar registro DNS (o apex é `updated in-place`, evitando a janela de NXDOMAIN em que o domínio cai na Squarespace).
3. **Atualizar de novo** `VM_HOST` e `OBSERVABILITY_PRIVATE_IP` — o replace muda os IPs outra vez. O cert Origin CA e o Turnstile **não** mudam nesse passo (são recursos Cloudflare, não recriados pelo replace das instâncias).
4. **Disparar na ordem**: `deploy-infra` → `deploy-api` → `deploy-web` → `deploy-observability`. Os três primeiros serializam pelo grupo `deploy-vm`; o de observabilidade roda em paralelo, por ter concurrency própria.
5. **Restaurar os dumps** do [T01](./01-salvaguarda-dados.md), se ainda fizer sentido — são dados de teste de MVP e o usuário já disse que a perda não implica nada. Decidir na hora se vale o esforço.
6. **Atualizar os IPs** em `docs/infrastructure.md` (hoje ainda listam `167.126.6.162` / `10.0.1.155` / `10.0.2.51`, todos mortos).
7. Fechar o checklist deste ticket e o da [T05](./05-fragmentar-envs.md) — o item "uma release real de api e de web passando pelo caminho novo" só fecha depois disso.

## Retomada concluída (2026-08-17)

`terraform apply -replace` das duas instâncias via API do Terraform Cloud (workspace `oracle-server` é VCS-connected, `apply` pela CLI é recusado — mesmo caminho documentado acima pro `destroy`). Plano bateu com o esperado: 2 destroy + 2 add (só as instâncias), 5 update in-place (DNS + dynamic group), **nenhum registro DNS destruído** — a lição da janela pro Squarespace não se repetiu.

IPs novos: `164.152.241.127` (A1.Flex) / `10.0.1.200` (privado) / `10.0.2.55` (E2.1.Micro). `VM_HOST`/`OBSERVABILITY_PRIVATE_IP` atualizados como vars do repo, `docs/infrastructure.md` atualizado (devops#96). `cloud-init status` = `done` nas duas VMs, sem passo manual.

Disparados na ordem: `deploy-infra` → `deploy-api` → `deploy-web` → `deploy-observability` — os quatro passaram.

**Achado adicional, fora do escopo do teardown em si**: `api` entrou em crash loop na VM nova — `BETTER_AUTH_SECRET` é obrigatório no schema de env desde o PR#86 (fundação Better Auth), mas o `deploy-api.yml` nunca renderizava essa variável. Só existia num `.env` local de um worktree Orca (gitignored), nunca propagado pros secrets de produção — por isso nunca apareceu em dev/CI. Criados `BETTER_AUTH_SECRET` e `RESEND_FROM_EMAIL` no Environment `api-production`, e o render passou a incluir os dois mais `EMAIL_PROVIDER=resend` (devops#97) — o `RESEND_API_KEY` já existia como secret desde 24/07, mas nunca era lido.

Dumps do T01 **não restaurados** — decisão do usuário: dado de teste de MVP, sem nada relevante a preservar.

Health check final: `api.oikos.company/health` (200), `oikos.company` (200), `grafana.oikos.company` (302, login), `minio.oikos.company` (200).

### Pendências que não bloqueiam a retomada

- **Secrets órfãos em `api-production`** (`POSTGRES_*`, `REDIS_PASSWORD`, `MINIO_*`, `CLIENT_API_KEY`, `TURNSTILE_*`): só remover depois de uma release real de `api` e de `web` passar pelo caminho novo, como registrado no [T05](./05-fragmentar-envs.md).
- **`cloudflare/.env.cloudflare` local** guarda um token da Cloudflare **inválido** (`{"success":false,"code":1000,"Invalid API Token"}`). Não é o token que o Terraform usa (esse vive no workspace do TFC e está funcionando), mas confunde. Apagar ou atualizar.
- **Revisão de `scripts/` e `docker/systemd/`**: ver [T09](./09-revisar-scripts-e-systemd.md).
- **`web#51`**: o `AccountMenuButton` nunca foi plugado no header — o `web` em `development` está sem Entrar, Registrar e acesso ao dashboard. Bloqueia o [T08](./08-padronizar-ci-api-web.md).
