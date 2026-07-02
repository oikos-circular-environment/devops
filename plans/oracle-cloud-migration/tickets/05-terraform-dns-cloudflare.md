# T5 — `devops`: Terraform — DNS + Cloudflare Access

**Status**: Em andamento — código do módulo `infra/terraform/dns/` escrito e validado localmente (`fmt`/`init`/`validate`), na branch `feature/t5-dns-cloudflare`. Falta rodar `plan`/`apply` de verdade e testar resolução DNS + Access no browser.
**Repositório**: `oikos-circular-environment/devops`

## Escopo

Registros DNS proxied do Cloudflare apontando pra VM `A1.Flex`, políticas de Cloudflare Access protegendo os hostnames administrativos, e o certificado Origin CA usado pelo nginx (T6).

## Fora de escopo

O `nginx.conf` que efetivamente usa o certificado (T6) — aqui só a parte Cloudflare/DNS/Access.

## Referências de spec

- `04-tech-plan.md` §Abordagem Arquitetural (Exposição pública)
- `docs/infrastructure.md` (Cloudflare — custos e limites)

## Dependências

T4 (precisa do IP público da `A1.Flex`).

## Checklist

- [x] Credenciais Cloudflare cadastradas como workspace variables sensitive no Terraform Cloud (usuário cadastra) — já feito na T4 (`cloudflare_account_id`, `cloudflare_api_token`)
- [x] `infra/terraform/dns/` — registro proxied `api.oikos.company` → IP público `A1.Flex`
- [x] `infra/terraform/dns/` — registro proxied `oikos.company` → IP público `A1.Flex`
- [x] `infra/terraform/dns/` — registro proxied `grafana.oikos.company` → IP público `A1.Flex`
- [x] `infra/terraform/dns/` — registro proxied `minio.oikos.company` → IP público `A1.Flex`
- [x] Política de Cloudflare Access cobrindo `grafana.oikos.company` (1 usuário — o desenvolvedor, `christiancnp@gmail.com`)
- [x] Política de Cloudflare Access cobrindo `minio.oikos.company` (mesmo usuário)
- [x] Confirmar que `api.oikos.company` e `oikos.company` **não** ficam atrás do Access (são públicos, só DNS proxied) — só `grafana`/`minio` têm `cloudflare_zero_trust_access_application`
- [x] Certificado Cloudflare Origin CA gerado — chave privada e CSR gerados via provider `tls` dentro do próprio Terraform, certificado assinado pela Cloudflare (`cloudflare_origin_ca_certificate`)
- [ ] Certificado cadastrado como secret no repo `devops` (`CLOUDFLARE_ORIGIN_CERT`/`CLOUDFLARE_ORIGIN_KEY`, usuário cadastra os valores) — pendente até o `apply` rodar; valores saem via `terraform output -raw origin_certificate_pem` / `origin_private_key_pem`
- [ ] `terraform plan`/`apply` revisado e rodado com sucesso
- [ ] Testar resolução DNS dos 4 hostnames + Access pedindo login em `grafana`/`minio`

## Definição de Pronto

Os 4 hostnames resolvem pro IP da `A1.Flex` via Cloudflare (proxied). Acessar `grafana.oikos.company`/`minio.oikos.company` no browser pede autenticação via Cloudflare Access antes de qualquer coisa chegar na VM.
