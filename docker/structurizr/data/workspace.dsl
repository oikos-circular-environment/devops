workspace "Oikos" "Plataforma colaborativa para a economia circular de residuos" {

    !identifiers hierarchical

    model {
        mobileUser = person "Usuario Mobile" "Usa o app Oikos para participar da economia circular de residuos"
        webUser = person "Usuario Web / Admin" "Acessa a plataforma web e dashboards"
        dev = person "Desenvolvedor" "Faz push para a branch production"

        oikos = softwareSystem "Oikos" "API + Web + Mobile + dados de producao" {
            mobileApp = container "Mobile App" "Instalado no dispositivo do usuario" "React Native / Expo" "Technology - Native Artifact Mobile"
            web = container "web" "Pagina inicial e area administrativa" "Next.js" "Technology - Next.js"
            nginx = container "nginx" "Roteia por hostname, termina TLS" "Reverse Proxy" "Technology - Nginx"

            api = container "api" "API REST" "Node.js / Fastify" "Technology - Node.js" {
                authComp = component "Auth" "Login, refresh de token, guards de rota" "TypeScript"
                usersComp = component "Users" "Gestao de usuarios e perfis" "TypeScript"
                companiesComp = component "Companies" "Empresas/cooperativas, horarios, servicos" "TypeScript"
                complaintsComp = component "Complaints" "Denuncia cidada com geolocalizacao" "TypeScript"
                marketComp = component "Market" "Marketplace de residuos" "TypeScript"
                wastesComp = component "Wastes" "Catalogo de tipos de residuo" "TypeScript"
                storageComp = component "Storage" "Upload/download de arquivos, proxy do MinIO" "TypeScript"
                queueComp = component "Queue" "Filas assincronas" "BullMQ"
                prismaComp = component "Prisma Client" "Acesso a dados" "Prisma ORM"
            }

            postgresql = container "postgresql" "Dados de aplicacao" "PostgreSQL" {
                tags "Database" "Technology - PostgreSQL"
            }
            redis = container "redis" "Filas (BullMQ)" "Redis" {
                tags "Database" "Technology - Redis"
            }
            minio = container "minio" "Storage de arquivos/imagens" "MinIO (S3-compatible)" {
                tags "Database" "Technology - MinIO"
            }
            observability = container "Observabilidade" "Metricas, logs, traces, dashboards, alertas" "Prometheus / Loki / Tempo / Grafana / Alertmanager" "Technology - Grafana"
        }

        mobileUser -> oikos.mobileApp "Usa" "Mobile UI (touch)"
        webUser -> oikos.web "Usa" "HTTPS"
        oikos.mobileApp -> oikos.nginx "Consome API" "HTTPS/REST"
        oikos.web -> oikos.nginx "Consome API" "HTTPS/REST"
        oikos.nginx -> oikos.api "Encaminha" "HTTP"
        oikos.nginx -> oikos.web "Encaminha" "HTTP"

        oikos.api.authComp -> oikos.api.prismaComp "Valida credenciais" "Chamada de funcao (in-process)"
        oikos.api.usersComp -> oikos.api.prismaComp "Le/escreve" "Chamada de funcao (in-process)"
        oikos.api.companiesComp -> oikos.api.prismaComp "Le/escreve" "Chamada de funcao (in-process)"
        oikos.api.complaintsComp -> oikos.api.prismaComp "Le/escreve" "Chamada de funcao (in-process)"
        oikos.api.marketComp -> oikos.api.prismaComp "Le/escreve" "Chamada de funcao (in-process)"
        oikos.api.wastesComp -> oikos.api.prismaComp "Le/escreve" "Chamada de funcao (in-process)"
        oikos.api.storageComp -> oikos.minio "Upload/download" "S3 SDK"
        oikos.api.complaintsComp -> oikos.api.queueComp "Enfileira notificacao" "Chamada de funcao (in-process)"
        oikos.api.queueComp -> oikos.redis "Enfileira/consome jobs" "Redis protocol (BullMQ)"
        oikos.api.prismaComp -> oikos.postgresql "Le/escreve" "SQL"
        oikos.api -> oikos.observability "Envia metricas/logs/traces" "OTel"
        oikos.web -> oikos.observability "Envia metricas/logs/traces" "OTel"

        dev -> oikos.mobileApp "git push (branch production)" "Git/SSH"

        prod = deploymentEnvironment "Production" {
            mobile = deploymentNode "Mobile" "Pipeline de build, distribuicao e telemetria do app mobile" "" {
                gh = deploymentNode "GitHub" "" "Git" {
                    repoProd = infrastructureNode "branch production" "Codigo-fonte do app mobile; branch monitorada pela integracao do Expo com o GitHub" "Git" "Technology - GitHub"
                    deployJob = infrastructureNode "deploy.yml" "Build arm64 (Buildx+QEMU), push GHCR, SSH deploy" "GitHub Actions Workflow" "Technology - GitHub Actions"
                    ghcr = infrastructureNode "GHCR" "Imagens privadas api/web" "GitHub Container Registry" "Technology - GitHub"
                }

                easCloud = deploymentNode "EAS Cloud" "Build e submit do app mobile" "Expo Application Services" {
                    easWorkflow = infrastructureNode "EAS Workflow" "Quality checks: lint, format, tests" "build-and-submit.yml" "Technology - Expo"
                    easBuild = infrastructureNode "EAS Build" "Compila .ipa (iOS) e .aab (Android), profile production" "EAS" "Technology - Expo"
                    easSubmit = infrastructureNode "EAS Submit" "Envia binario para as lojas" "EAS" "Technology - Expo"
                    easObserve = infrastructureNode "EAS Observe" "Monitora crashes, performance (cold/warm start, TTI) e adocao de updates em producao" "EAS" "Technology - Expo"
                }

                appStore = deploymentNode "Apple App Store Connect" "Distribuicao iOS + TestFlight" "SaaS" {
                    ascConnect = infrastructureNode "App Store Connect" "ascAppId 6786017565" "App Store Connect API" "Technology - App Store"
                }
                playConsole = deploymentNode "Google Play Console" "Distribuicao Android" "SaaS" {
                    playTrack = infrastructureNode "Play Console" "track alpha" "Google Play Developer API" "Technology - Google Play"
                }

                userDevice = deploymentNode "Dispositivo do Usuario" "iOS / Android / Browser" {
                    appInstance = containerInstance oikos.mobileApp
                }
            }

            cf = deploymentNode "Cloudflare Edge" "DNS, TLS e roteamento de borda" "CDN / Edge Network" {
                cfProxy = infrastructureNode "Edge Proxy" "Resolve DNS do dominio, termina TLS (certificado gerenciado) e roteia pro nginx" "Cloudflare" "Technology - Cloudflare"
            }

            tfc = deploymentNode "Terraform Cloud" "Executa runs de IaC e guarda o state remoto" "SaaS" {
                tfState = infrastructureNode "State remoto" "Runs VCS-driven, aplica mudancas de IaC" "Terraform Cloud" "Technology - Terraform"
            }

            oracle = deploymentNode "Oracle Cloud - Always Free" "" "Oracle Cloud Infrastructure (OCI)" {
                vcn = deploymentNode "VCN" "Rede privada isolada, compartilhada pelas duas VMs" "Virtual Cloud Network" {
                    tags "Oracle Cloud Infrastructure - Virtual Cloud Network"

                    vmA1 = deploymentNode "VM A1.Flex" "ARM, 2 OCPU / 12GB, ~150GB boot" "Ubuntu Server (ARM64)" {
                        tags "Oracle Cloud Infrastructure - Flex Virtual Machine"

                        dockerProd = deploymentNode "Docker Compose" "oikos-prod - docker-compose.prod.yml" "Docker Compose" "Technology - Docker" {
                            nginxD = containerInstance oikos.nginx
                            apiD = containerInstance oikos.api
                            webD = containerInstance oikos.web
                            pgD = containerInstance oikos.postgresql
                            redisD = containerInstance oikos.redis
                            minioD = containerInstance oikos.minio
                            cadvisorD = infrastructureNode "cAdvisor" "Coleta metricas de containers" "cAdvisor" "Technology - Google"
                            nodeExporterD = infrastructureNode "node-exporter" "Coleta metricas do host" "Prometheus node_exporter" "Technology - Prometheus"
                            alloyD = infrastructureNode "Alloy" "Agente unificado de telemetria (substitui otelcol em producao)" "Grafana Alloy" "Technology - Grafana"
                        }
                    }

                    vmE2 = deploymentNode "VM E2.1.Micro" "AMD, 1GB, ~50GB boot + swap 8-10GB" "Ubuntu Server (x86_64)" {
                        tags "Oracle Cloud Infrastructure - Burstable Virtual Machine"

                        dockerObs = deploymentNode "Docker Compose" "oikos-obs - docker-compose.observability.yml + prod override" "Docker Compose" "Technology - Docker" {
                            obsD = containerInstance oikos.observability
                        }
                    }
                }

                objStorage = deploymentNode "Object Storage" "20GB Always Free, pool separado" "Oracle Cloud Infrastructure - Object Storage (S3-compatible)" {
                    tags "Oracle Cloud Infrastructure - Buckets"

                    backupBucket = infrastructureNode "oikos-backups" "pg_dump + redis rdb, retencao 7 dias" "S3-compatible bucket"
                }
            }

            mobile.gh.repoProd -> mobile.easCloud.easWorkflow "Dispara workflow (push)" "Integracao GitHub do Expo (webhook)"
            mobile.easCloud.easWorkflow -> mobile.easCloud.easBuild "Quality checks aprovados" "Internal (EAS)"
            mobile.easCloud.easBuild -> mobile.easCloud.easSubmit "Build concluido" "Internal (EAS)"
            mobile.easCloud.easSubmit -> mobile.appStore.ascConnect "Submit iOS" "App Store Connect API"
            mobile.easCloud.easSubmit -> mobile.playConsole.playTrack "Submit Android" "Google Play Developer API"
            mobile.appStore.ascConnect -> mobile.userDevice.appInstance "Distribui app (instalacao/atualizacao)" "App Store / TestFlight"
            mobile.playConsole.playTrack -> mobile.userDevice.appInstance "Distribui app (instalacao/atualizacao)" "Google Play"
            mobile.userDevice.appInstance -> mobile.easCloud.easObserve "Envia metricas de uso, performance e crashes" "expo-observe SDK (HTTPS)"

            mobile.userDevice.appInstance -> cf.cfProxy "Acessa" "HTTPS"
            cf.cfProxy -> oracle.vcn.vmA1.dockerProd.nginxD "Proxied" "443, Security List restrita aos IPs do Cloudflare"
            oracle.vcn.vmA1.dockerProd.cadvisorD -> oracle.vcn.vmA1.dockerProd.alloyD "Expoe metricas de containers" "cAdvisor /metrics"
            oracle.vcn.vmA1.dockerProd.nodeExporterD -> oracle.vcn.vmA1.dockerProd.alloyD "Expoe metricas de host" "node_exporter /metrics"
            oracle.vcn.vmA1.dockerProd.alloyD -> oracle.vcn.vmE2.dockerObs.obsD "Envia metricas/logs/traces" "remote_write / push / OTLP gRPC, IP privado da VCN"
            mobile.gh.deployJob -> mobile.gh.ghcr "Push imagem" "Docker push (OCI Registry)"
            mobile.gh.deployJob -> oracle.vcn.vmA1.dockerProd.nginxD "SSH deploy" "docker compose pull/up, targeted por servico"
            tfc.tfState -> oracle.vcn.vmA1.dockerProd.nginxD "Provisiona/reconcilia infraestrutura" "VMs, rede, storage - OCI provider"
            tfc.tfState -> cf.cfProxy "Provisiona DNS" "Cloudflare provider"
            oracle.vcn.vmA1.dockerProd.apiD -> oracle.objStorage.backupBucket "Backup diario" "pg_dump/redis via cron"
        }
    }

    views {
        systemContext oikos "OikosContext" {
            include mobileUser oikos
            autoLayout lr 300 300
        }

        container oikos "OikosContainer" {
            include *
            exclude dev
            autoLayout tb 400 150
        }

        deployment oikos "Production" "MobileDeploy" {
            include *
            exclude prod.cf
            exclude prod.oracle
            exclude prod.tfc
            exclude prod.mobile.gh.deployJob
            exclude prod.mobile.gh.ghcr
            autoLayout lr 300 150
        }

        deployment oikos "Production" "OikosDeploy" {
            include prod.mobile.userDevice
            include prod.cf
            include prod.oracle
            exclude "prod.mobile.userDevice.appInstance -> prod.oracle.vcn.vmA1.dockerProd.nginxD"
            autoLayout tb 500 300
        }

        styles {
            element "Person" {
                shape person
            }
            element "Database" {
                shape cylinder
            }
        }

        theme oikos-oci
    }

    configuration {
        scope softwaresystem
    }

}
