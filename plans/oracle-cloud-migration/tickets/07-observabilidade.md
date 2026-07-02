# T7 — `devops`: Observabilidade Re-tunada

**Status**: Escrito e validado localmente, na branch `feature/t7-observabilidade`. Falta subir na VM real e confirmar visualização no Grafana (deferido pra revisão final, ticket 99).
**Repositório**: `oikos-circular-environment/devops`

## Escopo

Stack completa de observabilidade (Prometheus + Loki + Tempo + Grafana + Alertmanager) rodando na `E2.1.Micro` com limites re-tunados pra 1GB, e a camada de coleta (Alloy + cAdvisor + node-exporter) na `A1.Flex` alimentando essa stack — incluindo monitoramento de host e de container, não só de aplicação.

## Fora de escopo

Dashboards novos além dos 2 especificados em `docs/infra-monitoring-producao.md` (Infra Overview e Container Detail) — esses dois só foram **materializados como arquivo** agora (existiam só como especificação em prosa no doc, nunca tinham sido criados como JSON de verdade no repo).

## Referências de spec

- `00-epic-brief.md` §Decisão de Arquitetura (Observabilidade)
- `04-tech-plan.md` §Abordagem Arquitetural (orçamento de memória, observabilidade de host+container)
- `docs/infra-monitoring-producao.md` (dashboards e config do Alloy — origem, calibrado pra EC2)

## Dependências

T4 (precisa das duas VMs existindo e se comunicando por IP privado).

## Checklist

**Rede (pré-requisito, antes de qualquer coisa nessa ticket funcionar de ponta a ponta):**
- [x] `infra/terraform/network/` — regras de ingresso na Security List liberando, só a partir do CIDR da subnet **pública** (`10.0.1.0/24`, onde roda o Alloy na `A1.Flex`) — nunca da internet: Prometheus `remote_write` (9090), Loki `push` (3100), Tempo OTLP gRPC (4317), Grafana UI (3000). Achado ao planejar a T4: a OCI **não libera tráfego entre subnets da mesma VCN automaticamente** — precisa de regra explícita. Sem isso o `nginx` da `A1.Flex` não alcança o Grafana, e o Alloy não consegue mandar métricas/logs/traces pra `E2.1.Micro`.

**Na `E2.1.Micro`** — feito via `observability/docker-compose.observability.prod.yml` (override, novo — não mexe no arquivo base usado pelo dev local):
- [x] `prometheus`, limite re-tunado 200MB
- [x] `loki`, limite re-tunado 150MB
- [x] `tempo`, limite re-tunado 120MB (+ porta 4317 exposta pro host, necessária pro Alloy da outra VM alcançar via IP privado)
- [x] `grafana`, limite re-tunado 180MB
- [x] `alertmanager`, limite re-tunado 25MB
- [x] Soma dos 5 limites: 675MB de limite hard, com folga real pro SO/Docker dentro de 1GB
- [x] Deploy de produção sobe só esses 5 serviços (`docker compose -f docker-compose.observability.yml -f docker-compose.observability.prod.yml up -d prometheus loki tempo grafana alertmanager`) — `otelcol`/`promtail` ficam de fora (substituídos pelo Alloy da `A1.Flex`), mesmo continuando declarados no arquivo base pro dev local não quebrar

**Na `A1.Flex`** (dentro do `docker-compose.prod.yml` de T6 — ✅ escrito e validado com `alloy validate`):
- [x] Serviço `cadvisor` — métrica por container (CPU, RAM, rede, disco), 128MB
- [x] Serviço `node-exporter` — métrica de host (CPU, RAM, disco), 64MB
- [x] Serviço `alloy` (substitui otelcol) — 128MB
- [x] Config `alloy-prod.alloy` — recebe logs via OTLP da `api` (`pino-opentelemetry-transport`, não mais arquivo/tail), converte pra Loki via `otelcol.exporter.loki` com hint `loki.resource.labels` (`service.name`, `deployment.environment.name`) — sem isso os atributos não viram labels do Loki
- [x] Config `alloy-prod.alloy` — scrape `cadvisor:8080`
- [x] Config `alloy-prod.alloy` — scrape `node-exporter:9100`
- [x] Config `alloy-prod.alloy` — `remote_write` de métricas pro Prometheus da `E2.1.Micro` via IP privado
- [x] Config `alloy-prod.alloy` — `push` de logs pro Loki da `E2.1.Micro` via IP privado
- [x] Config `alloy-prod.alloy` — envio de traces (OTLP gRPC) pro Tempo da `E2.1.Micro` via IP privado
- [x] `sys.env(...)` usado em vez de `env(...)` (deprecado — `alloy validate` falhava com `env()`, achado só ao validar de verdade, não só formatar)

**Dashboards** (`observability/grafana/dashboards/`, carregados automaticamente pelo provisionamento do Grafana):
- [x] `infra-overview.json` — criado a partir da spec em `docs/infra-monitoring-producao.md` (4 linhas: host CPU/RAM/disco, CPU por container, RAM por container, rede por container), filtro `container_label_com_docker_compose_project="oikos-prod"`
- [x] `infra-container.json` — criado, variável `$service` (dropdown via `label_values`), painéis de CPU/throttling/RAM/rede/disco/restart count por container
- [ ] Confirmar visualização com dados reais no Grafana (precisa da stack rodando de verdade — deferido pra revisão final)

## Definição de Pronto

Abrir `grafana.oikos.company` (login com usuário/senha do Grafana) e ver, nos dois dashboards, dados reais de CPU/RAM/disco tanto do host `A1.Flex` quanto de cada container individualmente (api, web, postgresql, redis, minio, nginx).
