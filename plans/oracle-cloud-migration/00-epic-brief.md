# Migração de Produção para Oracle Cloud (Always Free) — Epic Brief

## Resumo

Hoje a "produção" do Oikos roda de forma improvisada: a stack `docker-compose.prod.yml` (api, postgresql, redis, minio) e a stack de observabilidade completa (`oikos/devops/observability`) rodam nesta máquina de desenvolvimento, expostas à internet como `api.oikos.company` via um túnel Cloudflare iniciado manualmente em um terminal (`cloudflared tunnel run --token ...`), atendendo usuários reais do app mobile. Esse túnel manual é apenas o método usado hoje para testes/simulação — não é o modelo de exposição que este épico usa em produção (ver decisão abaixo). Não existe nginx na frente da API, não existe CI/CD (`.github/workflows/` está vazio em `api`), e não há nenhum provisionamento de servidor real — só o par de chaves SSH da VM foi gerado.

O objetivo deste épico é migrar para uma infraestrutura real usando o Always Free Tier da Oracle Cloud (VM ARM `VM.Standard.A1.Flex`, 2 OCPU/12GB; e VM micro `VM.Standard.E2.1.Micro`, 1GB, para observabilidade — **ambas provisionadas do zero via Terraform**; Com separação clara de responsabilidades entre repositórios: cada projeto de aplicação (`api`, `mobile`, `web`) se autogerencia (format/lint/test + versionamento), e toda a camada de infraestrutura — provisionamento, build de imagem, deploy, observabilidade, exposição pública via Cloudflare — vive centralizada no `oikos/devops`, instrumentada como código (Terraform). O escopo inclui colocar o `web` (Next.js) no ar em `oikos.company` (servindo a página inicial de exemplo), além da API em `api.oikos.company`.

## Contexto & Problema

**Quem é afetado:** Usuários reais do app mobile (dependem da API hoje hospedada ad-hoc num laptop de desenvolvimento) e o time de desenvolvimento (sem CI/CD, sem processo de deploy repetível, sem separação entre código de aplicação e infraestrutura).

**Onde no produto:** Camada de infraestrutura — hospedagem da API e do `web`, observabilidade, e o caminho de exposição pública (`api.oikos.company` e `oikos.company`).

**Dor atual:**
- A "produção" depende de uma máquina de desenvolvedor ligada e de um túnel Cloudflare iniciado manualmente — sem resiliência, sem processo de restart.
- Não há CI/CD: mudanças vão para produção sem passar por format/lint/testes automatizados.
- Não há nginx na frente da API (proxy reverso ausente).
- Infraestrutura de deploy (`docker-compose.prod.yml`, `Dockerfile.prod`) hoje mora dentro do repo `api`, misturando responsabilidade de aplicação com responsabilidade de infraestrutura.
- A stack de observabilidade (`oikos/devops`) foi desenhada para um par de EC2 t3.small (2GB cada) — não existe versão dimensionada para as instâncias free tier da Oracle.
- Não há scripts/documentação de provisionamento da VM Oracle, nem versionamento/tagging automatizado nos repositórios.

**Resultado esperado:** API, banco, storage, observabilidade e o app `web` (Next.js) rodando de forma estável nas VMs Always Free da Oracle — `api.oikos.company` servindo a API e `oikos.company` servindo a página inicial do `web`, ambos atrás de DNS proxied do Cloudflare (sem túnel). Cada repo de aplicação roda seu próprio CI (format/lint/test) e versiona automaticamente via SemVer ao chegar em produção; o `devops` centraliza toda a infraestrutura como código (Terraform) e reage automaticamente a novas versões, buildando e implantando sem intervenção manual. Dados de produção migrados da máquina atual para a VM Oracle com o mínimo de downtime possível.

## Decisão de Arquitetura: Separação de Responsabilidades

**Todo repositório de aplicação (`api`, `mobile`, `web`)** roda seu próprio CI no GitHub Actions com a mesma responsabilidade — **format → lint → testes** (no `api`: unit, integration, e2e) — e nada além disso. Nenhum Dockerfile de produção, docker-compose de deploy, config de nginx, ou script de infraestrutura vive nesses repositórios.

**`oikos/devops`** é o único dono de infraestrutura:
- **Terraform** (providers OCI + Cloudflare) instrumenta, do zero: as duas VMs (`A1.Flex` para api+web, `E2.1.Micro` para observabilidade), rede/Security List (porta 443 liberada só para os ranges de IP do Cloudflare), e os registros DNS proxied do Cloudflare (`A` records para `api.oikos.company` e `oikos.company` apontando para os IPs públicos das VMs) — **sem Cloudflare Tunnel em produção**. Tudo (as duas VMs, rede, DNS) é criado do zero pelo Terraform, sem import de recurso existente no state.
- **State do Terraform**: usar backend remoto persistente (não local/efêmero), para que `apply` sempre reconcilie com os recursos já criados em execuções anteriores em vez de recriar/duplicar VM, rede ou registros DNS a cada execução — importante já que este é o único mecanismo de provisionamento (nenhuma VM é criada manualmente daqui pra frente).
- **`docker-compose.prod.yml` e `Dockerfile.prod`** migram inteiramente do `api` para o `devops` (inclusive a simulação local de produção deixa de existir no `api`), e ganham um serviço/`Dockerfile.prod` equivalente para o `web` (Next.js), buildado e implantado pelo mesmo pipeline.
- **nginx**: novo `nginx.conf` como reverse proxy para `api.oikos.company` (→ container `api`) e `oikos.company` (→ container `web`), terminando TLS com certificado Cloudflare Origin CA. Reaproveita o design já esboçado em `devops/plans/infra-monitoring-producao.md`.
- **Observabilidade**: stack completa (Prometheus + Loki + Tempo + Grafana + Alertmanager) na `E2.1.Micro`, com limites de memória re-tunados do zero para caber em 1GB (os limites atuais em `docker-compose.observability.yml` foram dimensionados pensando na EC2 t3.small de 2GB e somam ~1.9GB — não servem como estão). Orçamento alvo: ~875MB somados entre os 5 componentes, deixando ~150MB de folga pro SO/Docker — detalhar valores exatos por serviço no tech-plan. Swap file de 8-10GB (via cloud-init) como rede de segurança contra picos de memória, dentro do próprio boot volume da VM — não exige block volume extra. Alloy/cAdvisor/node-exporter rodam junto da API na VM ARM (12GB de sobra), enviando métricas/logs/traces para a `E2.1.Micro`.
- **Migração de dados**: dump/restore do Postgres + cópia dos buckets MinIO da máquina atual para a VM Oracle, com checklist de baixo downtime, antes do cutover do DNS.
- **App Next.js (`oikos.company`)**: dentro do escopo — `web` entra no mesmo pipeline de CI/deploy do `api` (format/lint/test + tag SemVer + `repository_dispatch` + build/deploy automático no `devops`). Critério de pronto deste épico: ao final, `oikos.company` deve servir a página inicial de exemplo do Next.js (sem exigir features de produto além disso).

## Versionamento e Fluxo de Release

- **Branches atuais**: `development` (integração) → `production` (branch de deploy). Não há branch `release` separado hoje.
- **SemVer por repositório**: cada repo de aplicação (`api`, `mobile`, `web`) versiona de forma independente, começando em `1.0.0`. Todo merge em `production` que passa no CI (format/lint/test) **incrementa automaticamente o PATCH** (`1.0.0 → 1.0.1 → 1.0.2 ...`). MAJOR/MINOR só mudam manualmente (feature grande ou breaking change).
- **Criação da tag**: automática, dentro do próprio workflow de CI do repo, ao detectar merge em `production` — sem intervenção manual.
- **Aviso ao devops**: após criar a tag, o repo dispara um `repository_dispatch` para `oikos/devops` com a versão/SHA. Esse fluxo de "cria versão → avisa devops → devops builda e faz deploy" vale para repositórios que rodam na infraestrutura (`api` e `web`). O `mobile` roda o mesmo CI de format/lint/test + versionamento, mas seu artefato vai para as lojas (EAS/App Store/Play Store), não para o `devops` — fora do escopo de deploy deste épico.
- **Deploy no devops**: totalmente automático, sem gate de aprovação manual — ao receber o `repository_dispatch`, o `devops` builda a imagem arm64 (Buildx + QEMU), publica no GHCR taggeada com a versão recebida, e atualiza a VM Oracle via SSH: (1) dump de segurança do Postgres, (2) `prisma migrate deploy` contra o banco de produção, (3) `docker compose pull && up -d`. Se a migration falhar, o deploy aborta sem trocar a versão em produção.

## Backup e Migrations de Banco de Dados

**Escopo deste épico (MVP): backup só dos bancos de dados (Postgres + Redis). MinIO fica fora do backup por enquanto** — o plano pós-MVP é tirar o MinIO da VM e mover para storage externo (Oracle Object Storage ou AWS, a definir; hoje a suspeita é que AWS sai mais barato), fora do escopo deste épico. Até lá, os arquivos do MinIO seguem sem backup automatizado — risco aceito conscientemente para o MVP.

- **Destino dos backups**: Oracle Object Storage (Always Free — 20GB, pool **separado** dos 200GB de Block Volume das VMs, 50.000 requisições/mês), com bucket provisionado via Terraform. Backups saem da VM para um domínio de falha diferente da própria VM.
- **Postgres**: `pg_dump` (formato custom, comprimido) via cron/systemd timer na VM ARM, diário, retendo os últimos 7 dias no Object Storage. Backup extra de segurança antes de cada `prisma migrate deploy` no fluxo de deploy (ver acima).
- **Redis**: precisa sobreviver a restart/crash da VM (fila com jobs críticos) — persistência habilitada (AOF ou RDB) com volume em disco, e entra no mesmo ciclo de backup diário para o Object Storage.
- **MinIO**: fora do backup neste épico (ver nota acima). A migração de dados inicial (`mc mirror` da máquina atual para a VM Oracle, no cutover) continua no escopo — é só o backup *recorrente* que fica de fora.
- **Migrations**: rodam automaticamente dentro do `.github/workflows/deploy.yml`, nunca manualmente — fazem parte do próprio fluxo de deploy do `repository_dispatch`, não de um passo separado.

## Escopo por Repositório

- **`oikos/api`** (este repo): `.github/workflows/ci.yml` com format → lint → unit → integration → e2e → (em `production`) tag SemVer automática → `repository_dispatch` para `oikos/devops`. Remoção de `docker-compose.prod.yml` e `Dockerfile.prod` (migram para `devops`) — atualizar README e `plans/self-hosted-infra/*` que os referenciam.
- **`oikos/mobile`**: mesmo padrão de CI (format/lint/test + tag SemVer automática em `production`), sem integração com o `devops` (fora de escopo aqui).
- **`oikos/web`** (Next.js): mesmo padrão de CI dos demais repos — format → lint → test → (em `production`) tag SemVer automática → `repository_dispatch` para `oikos/devops`. Nenhuma infraestrutura própria (sem Dockerfile/compose de deploy no repo).
- **`oikos/devops`**: novo `infra/terraform/` (OCI + Cloudflare), `docker/Dockerfile.prod` + `docker-compose.prod.yml` (recebidos do `api`, mais serviço equivalente para `web`), `nginx/nginx.conf` (novo, roteando `api.oikos.company` e `oikos.company`), `observability/docker-compose.observability.yml` ajustado para a `E2.1.Micro`, novo workflow `.github/workflows/deploy.yml` acionado por `repository_dispatch` (de `api` e `web`; build arm64 + push GHCR + backup de segurança + `prisma migrate deploy` + deploy SSH, sem gate manual), scripts de migração inicial de dados (pg_dump/restore, `mc mirror`) e de backup recorrente diário (Postgres/Redis → Oracle Object Storage, retenção de 7 dias; MinIO fora do backup neste épico).

## Restrições Confirmadas do Always Free Tier

Fonte: [documentação oficial Oracle](https://docs.oracle.com/pt-br/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm).

- **Compute:** `A1.Flex` — 2 OCPUs / 12GB de memória no total da tenancy (distribuível entre uma ou mais instâncias); `E2.1.Micro` — até 2 instâncias (1GB cada), todas no mesmo domínio de disponibilidade. As duas shapes podem coexistir na mesma tenancy/região.
- **Armazenamento:** 200GB de block storage **compartilhados entre todas as instâncias** (boot + block volumes combinados — o limite não é exclusivo do `A1.Flex`). Boot volume mínimo por instância: 47GB. Plano: `E2.1.Micro` com boot volume de ~50GB (mínimo + margem pequena), incluindo o swap file de 8-10GB dentro desse mesmo volume — folgado para os dados reais da stack de observabilidade (poucos GB no volume de uso atual do Oikos). Resta ~150GB para a VM `A1.Flex` (api + web + Postgres + MinIO).
- **Rede/saída:** 10TB/mês de egress — folgado para o volume atual.

## Itens em Aberto para o Tech Plan

- Distribuir os 200GB de storage compartilhado entre as duas VMs (tamanho de boot volume de cada uma), respeitando o mínimo de 47GB por instância.
- Backend do state do Terraform (ex: bucket OCI Object Storage, compatível S3, com backend `s3` do Terraform) — precisa ser remoto e persistente desde o primeiro `apply`, para evitar duplicar VMs/recursos em execuções futuras.
- Ferramenta exata para criação automática da tag SemVer no CI (ex: `mathieudutour/github-tag-action`, ou script próprio) e formato/segredo do `repository_dispatch` (fine-grained PAT em cada app repo, armazenado como secret).
- Onde documentar o bootstrap inicial das VMs (Docker, usuário de deploy, hardening SSH, criação do swap file de 8-10GB na `E2.1.Micro`): via `cloud-init` no Terraform ou script `remote-exec` separado.
- Orçamento de memória detalhado por componente da stack de observabilidade re-tunada (Prometheus/Loki/Tempo/Grafana/Alertmanager) para caber nos ~875MB alvo da `E2.1.Micro`, nos moldes da tabela já existente em `devops/plans/infra-monitoring-producao.md`.
- Estratégia para o certificado Cloudflare Origin CA usado pelo nginx (gerar manualmente e guardar como secret, ou automatizar via provider Terraform do Cloudflare).
- Runbook/drill de restore (Postgres, Redis) a partir do Object Storage — testar ao menos uma vez que os backups realmente restauram, não só que são gerados.
- Política de lifecycle do bucket de backup no Object Storage (auto-expirar dumps com mais de 7 dias via regra do próprio OCI, ou o script de backup cuida da rotação/exclusão).

## Próximo Passo

Próximo passo sugerido: `04-tech-plan.md`, detalhando arquivos a criar/mover em cada repo e o desenho do Terraform, reaproveitando o insumo técnico já existente em `devops/plans/infra-monitoring-producao.md`.
