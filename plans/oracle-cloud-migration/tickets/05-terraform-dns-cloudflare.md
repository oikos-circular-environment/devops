# T5 — `devops`: Terraform — DNS Cloudflare

**Status**: **Pronta.** `apply` rodou com sucesso, os 4 hostnames resolvem de verdade via internet real, e o login próprio de `grafana` e `minio` confirmados funcionando (2026-07-03). Certificado já cadastrado como secret no repo (confirmado em T9).
**Repositório**: `oikos-circular-environment/devops`

## Escopo

Registros DNS proxied do Cloudflare apontando pra VM `A1.Flex`, e o certificado Origin CA usado pelo nginx (T6).

## Fora de escopo

O `nginx.conf` que efetivamente usa o certificado (T6) — aqui só a parte Cloudflare/DNS. Cloudflare Access/Zero Trust foi avaliado e descartado (ver Decisões abaixo) — `grafana`/`minio` ficam protegidos só pelo login próprio de cada ferramenta.

## Decisões

- **Cloudflare Access removido do escopo do MVP** (decisão de 2026-07-02): a proteção extra do Zero Trust foi considerada overengineering neste estágio. `grafana.oikos.company` e `minio.oikos.company` seguem DNS proxied, mas protegidos apenas pelo usuário/senha forte de cada ferramenta (Grafana e MinIO console têm autenticação própria). Pode ser revisitado depois se o projeto crescer.

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
- [x] Certificado Cloudflare Origin CA gerado — chave privada e CSR gerados via provider `tls` dentro do próprio Terraform, certificado assinado pela Cloudflare (`cloudflare_origin_ca_certificate`)
- [x] Token da Cloudflare com permissão `Zone → SSL and Certificates → Edit` (necessária pro Origin CA) — cadastrada pelo usuário
- [x] `terraform apply` rodado com sucesso — os 4 registros DNS, o certificado Origin CA, a security list (T7) e o bucket/policies de backup (T8) foram todos criados/atualizados de verdade
- [x] Testar resolução DNS dos 4 hostnames — `api.oikos.company`, `oikos.company`, `minio.oikos.company` (200) e `grafana.oikos.company` (302) confirmados via internet real (Cloudflare)
- [x] Confirmar login próprio funcionando em `grafana` com credencial forte — autenticação testada via API do Grafana
- [x] Confirmar login próprio funcionando em `minio` especificamente — testado e confirmado (2026-07-03)
- [x] Certificado cadastrado como secret no repo `devops` (`CLOUDFLARE_ORIGIN_CERT`/`CLOUDFLARE_ORIGIN_KEY`) — confirmado em T9, deploys reais já materializam o cert com sucesso

## Definição de Pronto

Os 4 hostnames resolvem pro IP da `A1.Flex` via Cloudflare (proxied), com o certificado Origin CA válido servindo HTTPS. `grafana.oikos.company`/`minio.oikos.company` pedem login com usuário/senha forte da própria ferramenta.
