# Infraestrutura Oracle Cloud — Recursos, Custos e Decisões

Referência central de como a infraestrutura de produção do Oikos (épico [`oracle-cloud-migration`](../plans/oracle-cloud-migration/00-epic-brief.md)) foi construída: limites/custos reais de cada serviço e o *porquê* de cada decisão de desenho no Terraform (`infra/terraform/`). Referências `(ver ticket NN)` apontam pro histórico de implementação em `plans/oracle-cloud-migration/tickets/`. Atualizar sempre que um provedor mudar preço/limite ou uma decisão de arquitetura mudar.

Doc irmão: [`docker-infra.md`](./docker-infra.md) cobre a camada de Docker/deploy (compose, pipeline CI/CD, observability). Diagramas C4 em [`architecture-diagrams.md`](./architecture-diagrams.md). Cenário hipotético de custo fora do Always Free (infra + assinaturas) em [`estimativa-custo-mensal.md`](./estimativa-custo-mensal.md).

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

### Decisões do módulo Compute

Shape filtra a arquitetura automaticamente (`A1.Flex` = ARM, `E2.1.Micro` = x86), então as `data "oci_core_images"` já retornam só imagens compatíveis. Variante "Minimal" (menos pacotes pré-instalados, equivalente a uma imagem Docker slim) escolhida em vez da imagem padrão — reduz baseline de RAM/disco, o que importa principalmente na `E2.1.Micro` (1GB, orçamento de memória apertado).

### Decisões do módulo Network

- **Regras de ingress só IPv4**: a VCN não tem IPv6 habilitado e as instâncias só recebem IP público IPv4 — regras IPv6 seriam config morta (a OCI rejeita a criação da Security List se a VCN não suportar o CIDR IPv6 referenciado).
- **SSH aberto pra `0.0.0.0/0`** — decisão consciente: projeto solo, sem bastion dedicado, IP residencial dinâmico. Hardening fica por conta do `cloud-init` (autenticação só por chave, sem senha, sem login root). Na subnet privada essa regra é inofensiva — sem IP público, não há como a internet alcançar a porta de qualquer forma.
- **Portas de observabilidade restritas à subnet pública** `(ver ticket 07)`/`(ver ticket 04)`: só a partir de `10.0.1.0/24` (onde roda o Alloy, na A1.Flex), nunca da internet. Sem isso, a OCI bloqueia esse tráfego mesmo sendo intra-VCN.
- **`dns_label` da subnet pública mantido igual ao original** (`oikossub`) de propósito: é um campo imutável (`ForceNew`) na OCI — mudar o valor destruiria/recriaria a subnet mesmo com um `moved` block preservando o endereço do recurso no state.

## Endereços dos serviços (acesso interno e externo)

Referência rápida de como chegar em cada serviço rodando nas VMs — consolidado a partir de `docker-compose.prod.yml`, `nginx.conf` e `network/main.tf` (`infra/terraform/`), sem informação nova além do que já está nesses arquivos.

| VM | IP público | IP privado |
|---|---|---|
| `oikos-app` (A1.Flex) | `164.152.241.127` | `10.0.1.200` |
| `oikos-observability` (E2.1.Micro) | — (sem IP público, por design) | `10.0.2.55` |

A `E2.1.Micro` não tem IP público, então SSH só via bastion pela `A1.Flex` (`ssh -J` não propaga a identidade explícita `-i` pro salto, por isso `ProxyCommand` explícito):

```bash
ssh -i <chave> -o ProxyCommand="ssh -i <chave> -W %h:%p deploy@164.152.241.127" deploy@10.0.2.55
```

| Serviço | Endereço interno (rede Docker) | Endereço externo | Como acessar hoje |
|---|---|---|---|
| postgresql | `postgresql:5432` | nenhum (porta não publicada no host) | `docker compose exec postgresql psql -U $POSTGRES_USER -d $POSTGRES_DB` via SSH, **ou** túnel SSH (Beekeeper/DBeaver/TablePlus) direto pro IP interno do container — ver nota abaixo |
| redis | `redis:6379` | nenhum | `docker compose exec redis redis-cli -a $REDIS_PASSWORD` via SSH, **ou** túnel SSH direto pro IP interno do container — ver nota abaixo |
| minio (S3 API) | `minio:9000` | nenhum, nunca exposto (comentário explícito em `nginx.conf`) | SSH na A1.Flex + `docker compose exec` ou `mc` dentro do container |
| minio (console) | `minio:9001` | `https://minio.oikos.company` (proxied) | Browser, login com `MINIO_ACCESS_KEY`/`MINIO_SECRET_KEY` |
| api | `api:3333` | `https://api.oikos.company` (proxied) | Browser/HTTP client |
| web | `web:3000` | `https://oikos.company` / `https://www.oikos.company` (proxied) | Browser |
| nginx | — | `443` na A1.Flex, atrás do proxy Cloudflare | — |
| prometheus | `10.0.2.55:9090` | nenhum (Security List só permite `10.0.1.0/24`) | SSH bastion na E2.1.Micro |
| loki | `10.0.2.55:3100` | nenhum (só `10.0.1.0/24`) | SSH bastion na E2.1.Micro |
| tempo | `10.0.2.55:4317` (gRPC OTLP) | nenhum (só `10.0.1.0/24`) | SSH bastion na E2.1.Micro |
| grafana | `10.0.2.55:3000` | `https://grafana.oikos.company` (proxied) | Browser, login próprio |
| alertmanager | `10.0.2.55:9093` | nenhum, nem da subnet pública (sem regra na Security List) | SSH bastion na E2.1.Micro |

Credenciais de `postgresql`/`redis`/`minio` ficam em `.env.prod` na VM (`POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB`, `REDIS_PASSWORD`, `MINIO_ACCESS_KEY`/`MINIO_SECRET_KEY` — nomes das variáveis, os valores nunca ficam neste doc).

Para instruções campo a campo de como conectar um gerenciador de banco GUI (Beekeeper/DBeaver/TablePlus) via túnel SSH, ver seção abaixo.

### Conectando um gerenciador de banco (Beekeeper Studio) via túnel SSH

**Passo 1 — obter o IP interno do container** (rodar via SSH na A1.Flex; refazer após cada redeploy):

Postgres:
```bash
ssh deploy@164.152.241.127 "docker inspect oikos-prod-postgresql-1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'"
```

Redis:
```bash
ssh deploy@164.152.241.127 "docker inspect oikos-prod-redis-1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'"
```

**Postgres** — IP interno atual: `172.18.0.3`.

**Passo 2 — preencher o formulário de conexão** (Beekeeper tem túnel SSH nativo pra Postgres; mesma lógica pra DBeaver/TablePlus):

| Campo | Valor |
|---|---|
| Connection Type | `Postgres` |
| Authentication Method | `Username / Password` |
| Connection Mode | `Host and Port` |
| Host | `172.18.0.3` |
| Port | `5432` |
| Enable SSL | `Off` |
| User | `$POSTGRES_USER` (valor em `.env.prod`) |
| Password | `$POSTGRES_PASSWORD` |
| Default Database | `$POSTGRES_DB` |
| SSH Tunnel | `On` |
| SSH Hostname | `164.152.241.127` |
| Port (SSH) | `22` |
| SSH Authentication | `Key File` |
| SSH Username | `deploy` |
| Private Key File | caminho local da chave privada do usuário `deploy` (a mesma usada em `SSH_DEPLOY_KEY`, ver `docs/terraform-cloud-credentials-setup.md` §9.1) |
| Key File Passphrase | passphrase da chave, se houver |
| Keepalive Interval | `60` |

**Rodando os seeds contra produção**: `api/scripts/seed-prod.ts` (`npm run seed:prod`, no repo `api`) automatiza o fluxo acima — descobre o IP do container, lê as credenciais do `.env.prod` na VM via SSH, abre o túnel e roda `npm run seed` com o `DATABASE_URL` correto, fechando o túnel ao final. Uso esperado: manutenção pontual ou povoamento de infra nova, não o fluxo normal de dev (que roda contra o Postgres local). Sem guarda contra os usuários fake do `seedUsers` — fazem parte do povoamento de dados do MVP.

```bash
DEST_SSH_HOST=164.152.241.127 DEST_SSH_KEY=<caminho-da-chave> npm run seed:prod
```

**Redis** — IP interno atual: `172.18.0.2`. O Beekeeper não tem campo de túnel SSH pra conexões Redis, então o túnel precisa ser aberto manualmente antes de conectar:

```bash
ssh -L 6379:172.18.0.2:6379 deploy@164.152.241.127
```

Deixar esse terminal aberto (o túnel some se ele fechar) e, no Beekeeper, criar a conexão Redis com:

| Campo | Valor |
|---|---|
| Connection Type | `Redis` |
| Host | `localhost` |
| Port | `6379` |
| Password | `$REDIS_PASSWORD` (valor em `.env.prod`) |

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

### Decisões do módulo Storage

- **Instance Principal**: a A1.Flex se autentica no Object Storage sem nenhuma credencial estática embutida na VM (nem API key, nem token). A OCI emite um certificado efêmero automaticamente pra instância; o dynamic group reconhece essa instância específica pelo OCID, e a policy dá a ela permissão de gerenciar objetos só no bucket `oikos-backups`. Os scripts de backup (`backup-postgres.sh`/`backup-redis.sh`, ver [`docker-infra.md`](./docker-infra.md) §7) usam `oci ... --auth instance_principal`.
- **Policy explícita pro serviço de Object Storage**: o próprio serviço (não a VM) precisa de permissão explícita pra executar as ações de delete automáticas do lifecycle policy — sem essa policy o `apply` falha com `InsufficientServicePermissions`.
- **`time_sleep` de 30s antes do lifecycle policy**: policies de IAM da OCI levam alguns segundos pra propagar — sem esse delay o `apply` da lifecycle policy falha (mesmo erro `InsufficientServicePermissions`) mesmo com a policy já criada, porque tenta usá-la antes da propagação.
- **Retenção nativa OCI de 7 dias** (por prefixo `postgres/`/`redis/`) em vez de script customizado de rotação/limpeza `(ver ticket 08)` — decisão do tech-plan.

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
- **Cache Rules**: parte do plano Free (10 regras grátis, usamos 1) — cacheia `GET /storage/*` na edge (mídia servida via proxy do MinIO), TTL 30 dias, `override_origin` porque a API não manda `Cache-Control` na origem.
- **Custo atual: $0/mês.**

### Decisões de DNS & TLS (módulo `dns`)

- **Organização dos módulos**: os 3 `import` blocks dos `cloudflare_zone_setting` ficam no `main.tf` da raiz, não dentro do submódulo `dns` — `import` block dentro de módulo filho não é suportado, precisa ficar na raiz com `to` prefixado pelo caminho do módulo (`module.dns....`). Achado consultando a documentação oficial do provider, guia de migração v4→v5.
- **Certificado Origin CA**: chave privada e CSR gerados dentro do próprio Terraform (provider `tls`) — nunca saem da máquina/state gerenciado; o certificado assinado volta via API da Cloudflare. Os valores finais (cert + chave) precisam ser copiados **manualmente** pro GitHub Secrets do repo (`CLOUDFLARE_ORIGIN_CERT`/`CLOUDFLARE_ORIGIN_KEY`) — o assistente não automatiza esse cadastro, consistente com a regra de nunca manipular valor de secret `(ver ticket 06)`.
- **`lifecycle.ignore_changes = [hostnames]`** no certificado: a API da Cloudflare não garante a mesma ordem de `hostnames` no retorno — sem isso, todo `plan` detecta uma "mudança" (só a ordem) e força recriar o certificado (`hostnames` é `ForceNew` nesse recurso).
- **Auditoria de segurança de zona** (achado via API, 2026-07-03): provider v5 usa um resource por configuração (`cloudflare_zone_setting`), substituiu o `cloudflare_zone_settings_override` monolítico da v4.
- **SSL `full` → `strict`**: a zona estava em `full` — aceita qualquer certificado na origem sem validar, mesmo com o Origin CA já emitido especificamente pra permitir validação estrita. `strict` fecha esse gap de verdade.
- **TLS mínimo `1.0` → `1.2`**: TLS 1.0/1.1 são considerados obsoletos/inseguros (BEAST/POODLE, fora de conformidade PCI-DSS desde 2018). TLS 1.3 já estava habilitado (`tls_1_3` setting, não gerenciado aqui — default `on`).
- **`always_use_https` `off` → `on`**: requisição HTTP pura não redirecionava sozinha pra HTTPS antes dessa mudança.

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
