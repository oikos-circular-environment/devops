# T7 — `devops`: Observabilidade Re-tunada

**Status**: Não iniciado
**Repositório**: `oikos-circular-environment/devops`

## Escopo

Stack completa de observabilidade (Prometheus + Loki + Tempo + Grafana + Alertmanager) rodando na `E2.1.Micro` com limites re-tunados pra 1GB, e a camada de coleta (Alloy + cAdvisor + node-exporter) na `A1.Flex` alimentando essa stack — incluindo monitoramento de host e de container, não só de aplicação.

## Fora de escopo

Dashboards novos além dos 2 já existentes (reaproveitados de `docs/infra-monitoring-producao.md`, não recriados do zero).

## Referências de spec

- `00-epic-brief.md` §Decisão de Arquitetura (Observabilidade)
- `04-tech-plan.md` §Abordagem Arquitetural (orçamento de memória, observabilidade de host+container)
- `docs/infra-monitoring-producao.md` (dashboards e config do Alloy — origem, calibrado pra EC2)

## Dependências

T4 (precisa das duas VMs existindo e se comunicando por IP privado).

## Checklist

**Rede (pré-requisito, antes de qualquer coisa nessa ticket funcionar de ponta a ponta):**
- [ ] `infra/terraform/network/` — adicionar regras de ingresso na Security List liberando, só a partir do CIDR da subnet privada (`10.0.1.0/24`, não pra internet): Prometheus `remote_write` (9090), Loki `push` (3100), Tempo OTLP gRPC (4317), Grafana UI (3000). Achado ao planejar a T4: a OCI **não libera tráfego entre VMs da mesma subnet automaticamente** — precisa de regra explícita mesmo sendo intra-VCN, diferente de outras clouds. Sem isso o `nginx` da `A1.Flex` não alcança o Grafana, e o Alloy da `A1.Flex` não consegue mandar métricas/logs/traces pra `E2.1.Micro`.

**Na `E2.1.Micro`:**
- [ ] `observability/docker-compose.observability.yml` — `prometheus`, limite re-tunado (~200MB)
- [ ] `observability/docker-compose.observability.yml` — `loki`, limite re-tunado (~150MB)
- [ ] `observability/docker-compose.observability.yml` — `tempo`, limite re-tunado (~120MB)
- [ ] `observability/docker-compose.observability.yml` — `grafana`, limite re-tunado (~180MB)
- [ ] `observability/docker-compose.observability.yml` — `alertmanager`, limite re-tunado (~25MB)
- [ ] Soma dos 5 limites fica em ~875MB, com folga pro SO/Docker dentro de 1GB

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

**Dashboards:**
- [ ] Adaptar dashboard "Infra Overview" pro novo ambiente (filtro `container_label_com_docker_compose_project="oikos-prod"` continua válido)
- [ ] Adaptar dashboard "Container Detail" pro novo ambiente
- [ ] Confirmar visualização de CPU/RAM/rede/disco por container e do host consolidado no Grafana

## Definição de Pronto

Abrir `grafana.oikos.company` (via Cloudflare Access) e ver, nos dois dashboards, dados reais de CPU/RAM/disco tanto do host `A1.Flex` quanto de cada container individualmente (api, web, postgresql, redis, minio, nginx).
