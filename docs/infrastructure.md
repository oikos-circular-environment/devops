# Infraestrutura Oracle Cloud — Recursos e Custos

Referência viva dos limites e custos reais de cada serviço usado na infraestrutura de produção do Oikos (épico [`oracle-cloud-migration`](../plans/oracle-cloud-migration/00-epic-brief.md)). Atualizar sempre que um provedor mudar preço/limite ou um novo serviço entrar no desenho.

## Oracle Cloud — Always Free Tier

Fonte: [documentação oficial](https://docs.oracle.com/pt-br/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm).

| Recurso | Limite | Uso planejado |
|---|---|---|
| Compute `A1.Flex` (Ampere/ARM) | 2 OCPUs / 12GB de memória (total da tenancy, distribuível) | 1 instância — api, web, postgres, redis, minio, nginx, coleta de observabilidade |
| Compute `E2.1.Micro` (AMD) | Até 2 instâncias, 1GB cada, mesmo domínio de disponibilidade | 1 instância — prometheus, loki, tempo, grafana, alertmanager |
| Block Storage (boot + block volumes) | **200GB combinados, compartilhados entre todas as instâncias** — não é exclusivo do `A1.Flex` | `A1.Flex` ~150GB / `E2.1.Micro` ~50GB (inclui swap file de 8-10GB). Boot volume mínimo por instância: 47GB |
| Object Storage (Standard+IA+Archive) | 20GB combinados, **pool separado** do Block Storage; 50.000 requisições/mês | Bucket `oikos-backups` (Postgres + Redis, retenção 7 dias) |
| Egress (saída) | 10TB/mês | Folgado pro volume atual |
| VCNs | 2 por tenancy | 1 VCN compartilhada pelas 2 VMs, 2 subnets (pública + privada) |
| NAT Gateway | Sem limite Always Free específico, sem cobrança por hora na OCI (diferente da AWS) | 1 NAT Gateway, só pra saída de internet da subnet privada (`E2.1.Micro`) |

**Ambas as shapes (`A1.Flex` + `E2.1.Micro`) podem coexistir na mesma tenancy/região** — confirmado na documentação oficial.

**Achado durante o `apply` da T4**: uma única subnet compartilhada com só Internet Gateway não funciona pra uma instância sem IP público — o Internet Gateway só roteia tráfego de/para instâncias com IP público, então a `E2.1.Micro` (sem IP público, por design) não tinha rota nenhuma pra internet, e o `cloud-init` falhava ao instalar o Docker. Correção: a VCN passou a ter 2 subnets (pública com rota pro Internet Gateway, privada com rota pro NAT Gateway), cada uma com sua própria route table.

## Terraform Cloud (state remoto)

- **Free tier "enhanced"** (vigente desde 31/03/2026, substituiu o free plan legado): até **500 recursos gerenciados grátis**, usuários ilimitados, 1 run concorrente, SSO incluso.
- Acima de 500 recursos: cobrança por recurso/mês (Essentials $0.10 / Standard $0.47 / Premium $0.99).
- **Uso estimado deste projeto**: ~15-19 recursos (2 VMs, VCN, 2 subnets, security list, internet gateway, NAT gateway, 2 route tables, bucket de backup, ~4 registros DNS Cloudflare) — muito abaixo do limite grátis.
- **Custo atual: $0/mês.**
- Escolhido em vez de backend `s3` num bucket OCI porque o backend `s3` do Terraform depende de lock via DynamoDB pra evitar `apply` concorrente corromper o state — a OCI não tem equivalente nativo. Terraform Cloud resolve isso nativamente (fila de runs).

Fontes: [Continuing HCP Terraform's enhanced free tier](https://www.hashicorp.com/en/blog/continuing-hcp-terraform-s-enhanced-free-tier-experience), [Terraform Cloud Pricing 2026](https://scalr.com/learning-center/terraform-cloud-pricing-changes).

## Object Storage — Backup automatizado (Lifecycle Policy)

- Billing de Object Storage inclui uma linha específica pra chamadas de API de Object Lifecycle Management (OLM) — não é uma categoria "grátis por natureza", é billing por operação (mesma tabela de PUT/POST/LIST/DELETE do tier Standard: ~$0,0034 por 10.000 requisições; GET no Standard é grátis).
- **Volume real**: 2 serviços (Postgres + Redis) com rotação de 7 dias ≈ 2 uploads + 2 deletes/dia ≈ **~120 requisições/mês** — 0,24% da cota de 50.000 grátis do Always Free.
- **Custo, mesmo no pior cenário** (se o delete automático não contasse na cota free): **$0,00000408/mês** — irrelevante.

Fontes: [Object Storage Object Lifecycle Management](https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/usinglifecyclepolicies.htm), [OCI Storage Pricing Guide](https://ocispecialists.com/blog/oci-storage-pricing-guide/).

## GHCR (GitHub Container Registry / GitHub Packages)

- Container image storage e bandwidth estão **atualmente gratuitos** no GHCR — diferente de outros tipos de pacote do GitHub Packages (npm, Maven etc.), que têm cota de 500MB storage / 1GB transferência/mês por plano.
- Pulls/pushes feitos **dentro de GitHub Actions** continuam grátis mesmo se essa política mudar no futuro.
- GitHub se compromete a avisar com **1 mês de antecedência** antes de qualquer mudança nessa política.
- Imagem da `api`/`web` fica **privada** (decisão do projeto) — sem custo adicional por isso hoje; exige só um PAT fine-grained (`read:packages`) pra `docker login` na VM.
- **Custo atual: $0/mês.**

Fonte: [GitHub Packages billing](https://docs.github.com/en/billing/concepts/product-billing/github-packages).

## Cloudflare

- **DNS proxied (orange-cloud) + Origin CA certificate**: parte do plano Free do Cloudflare, sem custo algum, sem limite relevante pro nosso uso.
- `grafana.oikos.company` e `minio.oikos.company` ficam só atrás do DNS proxied — sem Cloudflare Access/Zero Trust (avaliado e descartado como overengineering pro MVP, T5). Protegidos pelo login próprio de cada ferramenta (usuário/senha forte).
- **Custo atual: $0/mês.**

## Expo EAS (Mobile — Operação)

Não é gerenciado pelo `devops` — o `mobile` se autogerencia e publica direto nas lojas (fora do escopo de deploy deste épico, ver `00-epic-brief.md`). Documentado aqui só pra ter visibilidade completa de custo operacional do Oikos como um todo, num único lugar.

| Recurso | Limite do plano Free |
|---|---|
| EAS Build | 15 builds Android + 15 iOS por mês, fila de baixa prioridade, timeout de 45min, 1 build simultâneo |
| EAS Submit | Incluso, sem cota adicional documentada (envio pro Google Play e App Store) |
| EAS Update (OTA) | 1.000 MAUs (usuários ativos/mês), 100GiB de bandwidth global, 20GiB de storage, atualizações ilimitadas |
| EAS Workflows (CI/CD) | 60 minutos/mês, fila de baixa prioridade |

Sem rollover de crédito não utilizado entre meses. Pro estágio atual do Oikos (poucos usuários reais, builds esporádicas), o plano Free cobre a operação com folga. Ponto de atenção pra reavaliar: se o volume de builds (ex: múltiplos devs, múltiplos PRs/dia) ou o número de usuários ativos recebendo OTA update passar dos limites acima — aí sim entra um plano pago (a partir de $19/mês, com créditos de build e 3.000 MAUs).

**Custo atual: $0/mês.**

Fonte: [Expo — Subscriptions, plans, and add-ons](https://docs.expo.dev/billing/plans/), [Expo Pricing](https://expo.dev/pricing).

## Resumo de Custo Mensal

| Serviço | Custo |
|---|---|
| Oracle Cloud (2 VMs + storage + rede) | $0 (Always Free) |
| Terraform Cloud (state) | $0 (enhanced free tier) |
| Object Storage + Lifecycle Policy (backup) | $0 (~120 req/mês de 50.000 grátis) |
| GHCR (imagens privadas) | $0 (storage/bandwidth grátis) |
| Cloudflare (DNS, Origin CA) | $0 (Free plan) |
| Expo EAS (mobile — build/submit/update) | $0 (Free plan, fora do escopo de deploy do `devops`) |
| **Total** | **$0/mês** |

Nenhum componente desta arquitetura tem custo hoje. Os pontos de atenção pra reavaliar no futuro: crescimento além de 500 recursos no Terraform Cloud, mudança de política de gratuidade do GHCR (aviso prévio de 1 mês garantido), ou o `mobile` estourar os limites de build/MAU do plano Free do EAS.
