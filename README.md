# Oikos · devops

Infraestrutura, deploy e observabilidade da plataforma Oikos. Este repositório não tem código de produto. Ele define onde a `api` e o `web` rodam, como chegam lá e como são monitorados. O app `mobile` é distribuído pelas lojas via Expo e só consome a API.

Os diagramas abaixo seguem o modelo C4. A fonte deles é o workspace do Structurizr em [`docker/structurizr/data/workspace.dsl`](docker/structurizr/data/workspace.dsl). Aqui eles aparecem em Mermaid para ler direto no GitHub. Segredos, endereços IP e portas ficam de fora de propósito.

## Contexto

Quem usa o Oikos e com quais serviços externos ele conversa.

```mermaid
C4Context
    title Oikos: contexto do sistema

    Person(mobileUser, "Usuário do app", "Cidadão, cooperativa ou empresa que usa o app")
    Person(webUser, "Usuário web / moderador", "Acessa o site e a área administrativa")
    Person(dev, "Equipe de desenvolvimento", "Publica versões e opera a infraestrutura")

    System(oikos, "Oikos", "API, web e dados de produção")

    System_Ext(stores, "App Store e Google Play", "Distribuição do app mobile")
    System_Ext(expo, "Expo EAS", "Build, submit e telemetria do app mobile")
    System_Ext(cloudflare, "Cloudflare", "DNS, TLS, cache e proteção de borda")
    System_Ext(resend, "Resend", "E-mail transacional")
    System_Ext(github, "GitHub", "Código, Actions e registro de imagens (GHCR)")
    System_Ext(tfc, "Terraform Cloud", "Execução e state remoto da infraestrutura como código")

    Rel(mobileUser, stores, "Instala e atualiza o app")
    Rel(mobileUser, cloudflare, "Usa o app", "HTTPS")
    Rel(webUser, cloudflare, "Usa o site", "HTTPS")
    Rel(cloudflare, oikos, "Encaminha requisições")
    Rel(oikos, resend, "Envia e-mails")
    Rel(dev, github, "Publica versões")
    Rel(github, oikos, "Implanta imagens")
    Rel(tfc, oikos, "Provisiona rede, VMs e storage")
    Rel(tfc, cloudflare, "Provisiona DNS e regras")
    Rel(expo, stores, "Envia os binários")
```

## Containers

O que roda dentro do Oikos e como as partes se falam.

```mermaid
C4Container
    title Oikos: containers

    Person(user, "Usuário", "App mobile ou navegador")

    System_Boundary(oikos, "Oikos") {
        Container(mobile, "Mobile", "React Native / Expo", "App instalado no dispositivo")
        Container(nginx, "nginx", "Proxy reverso", "Termina TLS de origem e roteia por hostname")
        Container(web, "web", "Next.js", "Site público e área administrativa")
        Container(api, "api", "Node.js / Fastify", "API REST, autenticação com Better Auth, filas com BullMQ")
        ContainerDb(pg, "PostgreSQL", "PostGIS", "Dados da aplicação")
        ContainerDb(redis, "Redis", "BullMQ", "Filas de jobs assíncronos")
        ContainerDb(minio, "MinIO", "S3 compatível", "Imagens e anexos")
        Container(obs, "Observabilidade", "Prometheus, Loki, Tempo, Grafana, Alertmanager", "Métricas, logs, traces, painéis e alertas")
    }

    System_Ext(resend, "Resend", "E-mail transacional")

    Rel(user, mobile, "Usa")
    Rel(mobile, nginx, "Chama a API", "HTTPS")
    Rel(user, nginx, "Acessa o site", "HTTPS")
    Rel(nginx, web, "Encaminha")
    Rel(nginx, api, "Encaminha")
    Rel(web, api, "Chama a API")
    Rel(api, pg, "Lê e escreve", "SQL")
    Rel(api, redis, "Enfileira e consome jobs")
    Rel(api, minio, "Envia e lê arquivos", "S3")
    Rel(api, resend, "Envia e-mails")
    Rel(api, obs, "Telemetria", "OTLP")
    Rel(web, obs, "Telemetria", "OTLP")
```

A `api` é organizada em módulos: `auth` (Better Auth), `accounts`, `profiles`, `companies`, `wastes`, `market`, `complaints` (denúncia cidadã com geolocalização), `moderation` (denúncias internas e suporte) e `storage` (proxy do MinIO).

## Implantação em produção

Tudo roda no plano Always Free da Oracle Cloud, em duas VMs dentro da mesma rede privada (VCN).

```mermaid
C4Deployment
    title Oikos: implantação em produção

    Deployment_Node(device, "Dispositivo do usuário", "iOS, Android ou navegador") {
        Container(mobileI, "Mobile / navegador", "Cliente")
    }

    Deployment_Node(cf, "Cloudflare", "Borda") {
        Container(edge, "Proxy de borda", "Cloudflare", "DNS, TLS, cache de mídia, Turnstile")
    }

    Deployment_Node(oci, "Oracle Cloud", "Always Free") {
        Deployment_Node(vcn, "VCN", "Rede privada") {
            Deployment_Node(app, "VM de aplicação", "A1.Flex, ARM64, Ubuntu") {
                Deployment_Node(compose, "Docker Compose", "oikos-prod") {
                    Container(nginxD, "nginx", "Proxy reverso")
                    Container(apiD, "api", "Node.js")
                    Container(webD, "web", "Next.js")
                    ContainerDb(pgD, "PostgreSQL", "PostGIS")
                    ContainerDb(redisD, "Redis", "BullMQ")
                    ContainerDb(minioD, "MinIO", "S3")
                    Container(alloyD, "Alloy", "Grafana Alloy", "Coleta métricas, logs e traces junto com cAdvisor e node-exporter")
                }
            }
            Deployment_Node(obsVm, "VM de observabilidade", "E2.1.Micro, x86_64, Ubuntu") {
                Container(obsD, "Observabilidade", "Prometheus, Loki, Tempo, Grafana, Alertmanager")
            }
        }
        Deployment_Node(os, "Object Storage", "Bucket de backup") {
            ContainerDb(bucket, "oikos-backups", "S3 compatível", "Retenção por lifecycle")
        }
    }

    Rel(mobileI, edge, "HTTPS")
    Rel(edge, nginxD, "HTTPS, só a partir dos IPs da Cloudflare")
    Rel(nginxD, apiD, "Encaminha")
    Rel(nginxD, webD, "Encaminha")
    Rel(apiD, pgD, "SQL")
    Rel(apiD, redisD, "Jobs")
    Rel(apiD, minioD, "S3")
    Rel(alloyD, obsD, "Telemetria pela rede privada")
```

Pontos que valem saber:

- A VM de aplicação só aceita HTTPS vindo dos blocos de IP da Cloudflare. Ninguém fala direto com a origem pelo site.
- A VM de observabilidade não tem IP público. Ela só recebe tráfego da VM de aplicação, pela rede privada.
- Banco, Redis e a API S3 do MinIO não são expostos para fora do Docker. O Grafana e o console do MinIO passam pelo nginx e exigem login próprio.
- O acesso administrativo às VMs é só por SSH com chave. Senha e login de root ficam desativados pelo cloud-init.
- O bucket de backup existe, mas hoje não há rotina de backup rodando. O redesenho está na [devops#90](https://github.com/oikos-circular-environment/devops/issues/90).

## Entrega contínua

Cada repositório de produto gera a própria versão. Este repositório só implanta.

```mermaid
C4Dynamic
    title Oikos: do merge em production até a VM

    Container(repo, "api / web", "GitHub", "Merge em production gera tag SemVer")
    Container(deploy, "deploy-api / deploy-web", "GitHub Actions (devops)", "Build arm64 e deploy")
    Container(ghcr, "GHCR", "Registro de imagens", "Imagens privadas")
    Container(vm, "VM de aplicação", "Docker Compose", "Atualiza só o serviço alterado")

    Rel(repo, deploy, "1. Dispara com versão e SHA", "repository_dispatch")
    Rel(deploy, ghcr, "2. Publica a imagem")
    Rel(deploy, vm, "3. Migra e sobe o container", "SSH")
    Rel(vm, ghcr, "4. Baixa a imagem")
```

| Workflow | Quando roda | O que faz |
|---|---|---|
| `deploy-api.yml` | Release da `api` ou execução manual | Build da imagem, migrations e deploy do container da API |
| `deploy-web.yml` | Release do `web` ou execução manual | Build da imagem e deploy do container do site |
| `deploy-infra.yml` | Push em `production` que mexe em `docker/` ou `nginx/` | Sincroniza arquivos e reconcilia a stack da VM de aplicação |
| `deploy-observability.yml` | Push em `production` que mexe em `observability/` | Reconcilia a stack da VM de observabilidade |

O app mobile segue outro caminho: o push na branch `production` do repositório `mobile` dispara o workflow do Expo EAS, que roda as checagens, compila e envia para App Store Connect e Google Play.

## Infraestrutura como código

O Terraform fica em [`infra/terraform`](infra/terraform) e roda no Terraform Cloud, que guarda o state remoto.

| Módulo | Recursos |
|---|---|
| `network` | VCN, sub-redes pública e privada, gateways e regras de firewall |
| `compute` | As duas VMs, com provisionamento por cloud-init |
| `storage` | Bucket de backup, lifecycle e permissão restrita à VM de aplicação |
| `dns` | Registros DNS, certificado de origem, cache de mídia e Turnstile na Cloudflare |

## Estrutura do repositório

| Pasta | Conteúdo |
|---|---|
| `docker/` | Compose e Dockerfiles de produção, e o workspace do Structurizr |
| `nginx/` | Configuração do proxy reverso |
| `observability/` | Stack de observabilidade, dashboards e alertas |
| `infra/terraform/` | Infraestrutura como código |
| `.github/` | Workflows de deploy e actions compartilhadas |
| `load-tests/` | Testes de carga com k6 |
| `docs/` | Decisões, runbooks e estimativa de custo |
| `plans/` | Planos e tickets em andamento |

## Documentação

- [Infraestrutura Oracle Cloud](docs/infrastructure.md): recursos, custos e decisões
- [Docker e deploy](docs/docker-infra.md): pipeline, segredos, capacidade e problemas conhecidos
- [Diagramas de arquitetura](docs/architecture-diagrams.md): como editar e exportar os diagramas C4
- [Runbook de restore](docs/backup-restore-runbook.md)
- [Credenciais do Terraform Cloud](docs/terraform-cloud-credentials-setup.md)
- [Estimativa de custo mensal](docs/estimativa-custo-mensal.md)

## Editando os diagramas

O workspace do Structurizr roda localmente:

```bash
docker compose -f docker/docker-compose.structurizr.yml up -d
```

Depois de alterar o `workspace.dsl`, atualize os diagramas Mermaid deste README para continuarem iguais ao modelo.
