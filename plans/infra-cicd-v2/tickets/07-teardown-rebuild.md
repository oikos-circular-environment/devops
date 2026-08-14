# T07 — Teardown e rebuild do zero

**Status**: não iniciada.
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

_(preencher durante a execução)_
