# T5 — `devops`: Terraform — DNS + Cloudflare Access

**Status**: Não iniciado
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

- [ ] Credenciais Cloudflare cadastradas como workspace variables sensitive no Terraform Cloud (usuário cadastra)
- [ ] `infra/terraform/dns/` — registro proxied `api.oikos.company` → IP público `A1.Flex`
- [ ] `infra/terraform/dns/` — registro proxied `oikos.company` → IP público `A1.Flex`
- [ ] `infra/terraform/dns/` — registro proxied `grafana.oikos.company` → IP público `A1.Flex`
- [ ] `infra/terraform/dns/` — registro proxied `minio.oikos.company` → IP público `A1.Flex`
- [ ] Política de Cloudflare Access cobrindo `grafana.oikos.company` (1 usuário — o desenvolvedor)
- [ ] Política de Cloudflare Access cobrindo `minio.oikos.company` (mesmo usuário)
- [ ] Confirmar que `api.oikos.company` e `oikos.company` **não** ficam atrás do Access (são públicos, só DNS proxied)
- [ ] Certificado Cloudflare Origin CA gerado
- [ ] Certificado cadastrado como secret no repo `devops` (`CLOUDFLARE_ORIGIN_CERT`/`CLOUDFLARE_ORIGIN_KEY`, usuário cadastra os valores)

## Definição de Pronto

Os 4 hostnames resolvem pro IP da `A1.Flex` via Cloudflare (proxied). Acessar `grafana.oikos.company`/`minio.oikos.company` no browser pede autenticação via Cloudflare Access antes de qualquer coisa chegar na VM.
