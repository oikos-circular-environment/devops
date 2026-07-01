# Oikos — Diagramas C4 (Infraestrutura de Produção)

Diagramas em Mermaid, notação C4 (System Context, Container, Deployment). Referem-se ao desenho descrito em [`plans/oracle-cloud-migration/04-tech-plan.md`](../plans/oracle-cloud-migration/04-tech-plan.md) e aos valores em [`infrastructure.md`](./infrastructure.md). Atualizar junto com qualquer mudança na Abordagem Arquitetural do tech-plan.

## System Context

Visão de mais alto nível: quem usa o Oikos e com quais sistemas externos ele se relaciona.

```mermaid
C4Context
    title Oikos — Diagrama de Contexto do Sistema

    Person(mobileUser, "Usuário Mobile", "Usa o app Oikos para participar da economia circular de resíduos")
    Person(admin, "Desenvolvedor/Admin", "Desenvolve, provisiona infra e monitora produção")

    System(oikos, "Oikos", "API + Web + dados de produção")

    System_Ext(cloudflare, "Cloudflare", "DNS proxied, TLS (Origin CA), Access (Zero Trust)")
    System_Ext(github, "GitHub", "Repositórios, Actions (CI/CD), Packages (GHCR)")
    System_Ext(terraformCloud, "Terraform Cloud", "State remoto + execução de plan/apply")
    System_Ext(oracleCloud, "Oracle Cloud", "Always Free — VMs, rede, Object Storage")

    Rel(mobileUser, cloudflare, "Acessa", "HTTPS, api.oikos.company")
    Rel(admin, cloudflare, "Acessa dashboards/console", "HTTPS via Cloudflare Access")
    Rel(cloudflare, oikos, "Encaminha tráfego", "DNS proxied → nginx")
    Rel(admin, github, "Desenvolve, aprova merges")
    Rel(github, oikos, "Builda e implanta nova versão", "repository_dispatch → build → SSH")
    Rel(terraformCloud, oracleCloud, "Provisiona/reconcilia infraestrutura")
    Rel(terraformCloud, cloudflare, "Provisiona DNS/Access")
    Rel(oikos, oracleCloud, "Roda em", "VMs Always Free")
```

## Container

Zoom nos containers que compõem o Oikos — inclui a divisão lógica entre a stack de aplicação e a stack de observabilidade (a separação física por VM fica no diagrama de Deployment).

```mermaid
C4Container
    title Oikos — Diagrama de Containers

    Person(mobileUser, "Usuário Mobile")
    Person(admin, "Desenvolvedor/Admin")
    System_Ext(cloudflare, "Cloudflare", "DNS, TLS, Access")
    System_Ext(githubActions, "GitHub Actions", "CI/CD, push pro GHCR")

    System_Boundary(oikos, "Oikos") {
        Container(nginx, "nginx", "Reverse Proxy", "Roteia por hostname, termina TLS (Origin CA)")
        Container(api, "api", "Node.js / Fastify", "API REST; expõe /storage/* como proxy do MinIO")
        Container(web, "web", "Next.js", "App web (página inicial)")
        ContainerDb(postgresql, "postgresql", "PostgreSQL", "Dados de aplicação")
        ContainerDb(redis, "redis", "Redis", "Filas (BullMQ), persistência AOF/RDB")
        ContainerDb(minio, "minio", "MinIO (S3-compatible)", "Storage de arquivos/imagens")
        Container(alloy, "Alloy / cAdvisor / node-exporter", "Grafana Alloy", "Coleta métricas/logs/traces")

        Container(prometheus, "prometheus", "Prometheus", "Armazena métricas")
        Container(loki, "loki", "Loki", "Armazena logs")
        Container(tempo, "tempo", "Tempo", "Armazena traces")
        Container(grafana, "grafana", "Grafana", "Dashboards")
        Container(alertmanager, "alertmanager", "Alertmanager", "Roteamento de alertas")
    }

    Rel(mobileUser, nginx, "HTTPS", "api.oikos.company")
    Rel(admin, nginx, "HTTPS via Cloudflare Access", "grafana.oikos.company / minio.oikos.company")
    Rel(nginx, api, "Encaminha")
    Rel(nginx, web, "Encaminha")
    Rel(nginx, grafana, "Encaminha")
    Rel(nginx, minio, "Encaminha (console)")
    Rel(api, postgresql, "Lê/escreve", "Prisma")
    Rel(api, redis, "Enfileira jobs", "BullMQ")
    Rel(api, minio, "Upload/download", "S3 SDK")
    Rel(alloy, prometheus, "remote_write")
    Rel(alloy, loki, "push")
    Rel(alloy, tempo, "OTLP gRPC")
    Rel(grafana, prometheus, "Consulta")
    Rel(grafana, loki, "Consulta")
    Rel(grafana, tempo, "Consulta")
    Rel(prometheus, alertmanager, "Envia alertas")
    Rel(githubActions, api, "Deploy (build + push + SSH)")
    Rel(githubActions, web, "Deploy (build + push + SSH)")
```

## Deployment

Onde cada container roda de fato — as duas VMs Oracle Always Free, o bucket de backup, e os sistemas externos (GitHub, Terraform Cloud, Cloudflare) que operam a infraestrutura.

```mermaid
C4Deployment
    title Oikos — Diagrama de Implantação

    Deployment_Node(userDevice, "Dispositivo do Usuário", "iOS / Android / Browser") {
        Container(mobileApp, "App Mobile / Browser")
    }

    Deployment_Node(cf, "Cloudflare Edge", "DNS proxied + Access") {
        Container(cfProxy, "TLS termination + Zero Trust")
    }

    Deployment_Node(oracle, "Oracle Cloud — Always Free") {
        Deployment_Node(vmA1, "VM A1.Flex", "ARM, 2 OCPU / 12GB, ~150GB boot") {
            Container(nginxD, "nginx")
            Container(apiD, "api")
            Container(webD, "web")
            ContainerDb(pgD, "postgresql")
            ContainerDb(redisD, "redis")
            ContainerDb(minioD, "minio")
            Container(alloyD, "Alloy / cAdvisor / node-exporter")
        }
        Deployment_Node(vmE2, "VM E2.1.Micro", "AMD, 1GB, ~50GB boot + swap 8-10GB") {
            Container(promD, "prometheus")
            Container(lokiD, "loki")
            Container(tempoD, "tempo")
            Container(grafanaD, "grafana")
            Container(amD, "alertmanager")
        }
        Deployment_Node(objStorage, "Object Storage", "20GB Always Free, pool separado") {
            Container(backupBucket, "oikos-backups", "pg_dump + redis rdb, retenção 7 dias")
        }
    }

    Deployment_Node(gh, "GitHub") {
        Deployment_Node(ghActions, "GitHub Actions Runner") {
            Container(deployJob, "deploy.yml", "Build arm64 (Buildx+QEMU), push GHCR, SSH deploy")
        }
        Container(ghcr, "GHCR", "Imagens privadas api/web")
    }

    Deployment_Node(tfc, "Terraform Cloud") {
        Container(tfState, "State remoto + runs VCS-driven")
    }

    Rel(mobileApp, cfProxy, "HTTPS")
    Rel(cfProxy, nginxD, "Proxied", "443, Security List restrita aos IPs do Cloudflare")
    Rel(alloyD, promD, "remote_write", "IP privado da VCN")
    Rel(alloyD, lokiD, "push", "IP privado da VCN")
    Rel(alloyD, tempoD, "OTLP gRPC", "IP privado da VCN")
    Rel(deployJob, ghcr, "Push imagem")
    Rel(deployJob, nginxD, "SSH deploy", "docker compose pull/up, targeted por serviço")
    Rel(tfState, nginxD, "Provisiona/reconcilia infraestrutura", "VMs, rede, storage — OCI provider")
    Rel(tfState, cfProxy, "Provisiona DNS/Access", "Cloudflare provider")
    Rel(apiD, backupBucket, "Backup diário", "pg_dump/redis via cron")
```
