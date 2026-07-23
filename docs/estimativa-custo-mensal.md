# Estimativa de Custo Mensal (cenário pago, fora do Always Free)

Doc irmão: [`infrastructure.md`](./infrastructure.md) documenta o custo **real** de hoje (R$ 0 / $0, tudo dentro de free tiers). Este doc é um exercício diferente: **quanto custaria em reais se a estrutura atual parasse de ser gratuita** — Oracle Cloud saindo do Always Free (preço de lista PAYG) mais as assinaturas/taxas que já são pagas fora do escopo do `devops` (Claude, Expo EAS, lojas de app). Útil como referência de orçamento, não como cobrança atual.

**Câmbio usado:** 1 USD ≈ R$ 5,08 (cotação do dia da estimativa, ver fonte). Atualizar se for reusar este doc mais adiante — câmbio muda o total sem nenhuma mudança de infra.

## 1. Infraestrutura Oracle Cloud (preço de lista PAYG)

Mesmos recursos provisionados em `infra/terraform/` (ver [`infrastructure.md`](./infrastructure.md) pros limites Always Free equivalentes), precificados como se o Always Free não existisse.

| Recurso | Config atual (Terraform) | Preço unitário (USD) | Custo/mês (USD) | Custo/mês (BRL) |
|---|---|---|---|---|
| VM `oikos-app` (`A1.Flex`) | 2 OCPU + 12 GB RAM | OCPU $0,01/h · RAM $0,0015/GB-h | $27,74 | ≈ R$ 141,00 |
| VM `oikos-observability` (`E2.1.Micro`) | 1 OCPU (billing) | $0,0255/OCPU-h | $18,62 | ≈ R$ 95,00 |
| Block Volume (boot) | 150 GB + 50 GB = 200 GB, tier *Balanced* (default) | $0,0255/GB storage + $0,017/GB performance (10 VPU) | $8,50 | ≈ R$ 43,00 |
| Object Storage (`oikos-backups`) | uso real baixo (~120 req/mês), bem abaixo dos 20 GB free | $0,0255/GB-mês | ~$0,05–0,50 | ≈ R$ 0,25–2,50 |
| NAT Gateway, VCN, IGW, Security List | — | sem cobrança por hora na OCI | $0 | R$ 0 |
| Egress (saída de internet) | — | OCI zerou egress globalmente (anúncio fev/2026) | $0 | R$ 0 |
| **Total infra** | | | **≈ $55/mês** | **≈ R$ 280,00/mês** |

Premissas: 730h/mês (padrão de billing de nuvem), tier de performance *Balanced* (default de boot/block volume — trocar pra "Lower Cost" cairia o Block Volume pra ~$5,10/mês ≈ R$ 26). Preço de lista OCI é praticamente uniforme entre regiões comerciais. Não inclui desconto de Universal Credits nem eventual IOF/variação cambial de fatura internacional.

## 2. Serviços e Ferramentas (fora da infra Oracle Cloud)

Categorias diferentes da infra: assinaturas de ferramenta/produtividade vs. taxas de distribuição em loja de apps.

| Categoria | Serviço | Plano/valor informado | Recorrência | Equivalente mensal (USD) | Equivalente mensal (BRL) |
|---|---|---|---|---|---|
| IA / Dev Tooling | Claude | $19/mês | Mensal | $19,00 | R$ 96,52 |
| Mobile — Build & Deploy (EAS) | Expo | $19/mês | Mensal | $19,00 | R$ 96,52 |
| Distribuição — iOS | Apple Developer Program | $99/ano | **Anual** | $8,25 (prorateado) | R$ 41,91 |
| Distribuição — Android | Google Play Console | $25 | **Pagamento único** (não recorrente) | — | R$ 127,00 (uma vez) |
| **Total recorrente/mês** | | | | **$46,25** | **R$ 235,02** |

**Apple vs. Android não são equivalentes por natureza da própria loja, não por escolha de config:**
- **Apple Developer Program** = $99/ano, **recorrente** (app sai da loja se não renovar).
- **Google Play Console** = $25, pago **uma única vez** na vida da conta, sem cobrança anual.

O valor do Android entra na tabela como custo único (R$ 127,00) — não soma no total recorrente mensal, só no primeiro mês (ou em qualquer mês em que a conta for criada).

## 3. Custo total combinado (infra + serviços)

| Bloco | Custo mensal (BRL) |
|---|---|
| Infra Oracle Cloud (seção 1) | ≈ R$ 280,00 |
| Serviços/ferramentas recorrentes (seção 2) | ≈ R$ 235,02 |
| **Total mensal recorrente** | **≈ R$ 515,00** |
| + Google Play (uma vez, primeiro mês) | + R$ 127,00 |

## Fontes

- [Ampere A1 Compute pricing — Oracle](https://www.oracle.com/cloud/compute/arm/)
- [Oracle Cloud Infrastructure Compute Pricing — economize.cloud](https://www.economize.cloud/resources/oci/pricing/compute/)
- [Compare Pricing on Oracle Block Volume](https://www.oracle.com/cloud/storage/block-volumes/pricing/)
- [Oracle OCI Announces Free Egress Pricing Globally](https://www.tcoiq.com/cloud-news/oracle-oci-announces-free-egress-pricing-globally-across-all-regions)
- [Cotação USD/BRL — Investing.com](https://br.investing.com/currencies/usd-brl)
- [Apple Developer Program Cost: The $99/Year Fee Explained (2026)](https://appbuilder24.com/blog/apple-developer-account-needed)
- [Google Play Developer Fee 2026: $25 + 12-Tester Rule](https://www.iconikai.com/blog/google-play-developer-account-fee-2026)
- [Claude Pricing (2026): Pro $20, Max $100, Team & API](https://appscribed.com/claude-pricing/)
