# T07 — Teardown e rebuild do zero

**Status**: **em andamento** — teardown executado em 2026-08-14, subida aguardando liberação do usuário.
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

- [ ] Confirmar [T01](./01-salvaguarda-dados.md) concluída e restore validado
- [ ] Confirmar [T06](./06-provisionamento-declarativo.md) validada em VM descartável
- [ ] `terraform destroy` completo
- [ ] `terraform apply` do zero
- [ ] Atualizar `vars.VM_HOST` e `vars.OBSERVABILITY_PRIVATE_IP` no repo `devops`
- [ ] Atualizar IPs em `docs/infrastructure.md`
- [ ] Conferir cloud-init concluído sem erro nas duas VMs (`cloud-init status`)
- [ ] Deploy `service=stack` para materializar a stack
- [ ] Restaurar os dumps de Postgres, Redis e MinIO
- [ ] Conferir DNS propagado e TLS válido nos domínios
- [ ] Deploy de `api` e de `web` nas últimas tags publicadas

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
