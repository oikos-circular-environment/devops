# Monitoramento de Infraestrutura — Produção (EC2 t3.small)

## Context

A stack de produção roda `api`, `postgresql`, `redis`, `minio` e `nginx` (ainda ausente) em um EC2 t3.small (2 vCPU, 2 GB RAM). Atualmente não há visibilidade de CPU, RAM e disco dos containers — as métricas OTel existentes cobrem apenas nível de aplicação. O objetivo é adicionar monitoramento de infraestrutura com visão por serviço e overview consolidado, sem ultrapassar o budget de memória da instância.

---

## Arquitetura

O padrão existente no `docker-compose.prod.yml` já é push: `promtail` empurra logs para `${LOKI_URL}`. A estratégia para métricas segue o mesmo modelo: exporters leves na EC2 de prod, um agente empurra para um **servidor de monitoramento dedicado** (segunda EC2).

```
EC2 t3.small — Producao                     EC2 t3.small — Monitoramento
├── base services                            ├── prometheus  (recebe remote_write)
│   ├── nginx (novo, reverse proxy)          ├── loki        (recebe logs)
│   ├── api                                  └── grafana     (dashboards)
│   ├── postgresql                                 ↑
│   ├── redis                                      │ VPC interno / Security Group
│   └── minio                                      │ (portas 9090 e 3100 restritas
└── --profile obs                                  │  ao IP da EC2 de prod)
    ├── cadvisor        (metricas container)        │
    ├── node-exporter   (metricas host)             │
    └── alloy  ─────────────────────────────────────┘
          ├── scrape cadvisor:8080
          ├── scrape node-exporter:9100 → remote_write → ${PROMETHEUS_REMOTE_WRITE_URL}
          └── tail /var/log/oikos/*.log  → loki.write  → ${LOKI_URL}
```

**Grafana Alloy** substitui o `promtail` atual porque unifica scrape de métricas + envio de logs em um único container, com footprint menor que dois processos separados.

**Segurança de rede:** as portas 9090 (Prometheus) e 3100 (Loki) do servidor de monitoramento devem ser restritas via AWS Security Group somente ao IP da EC2 de produção. A porta 3000 (Grafana) pode ser acessível via browser (HTTPS com senha) ou somente via SSH tunnel.

---

## Orçamento de Memória (EC2 t3.small — 2 GB)

| Serviço | Limite atual | Limite proposto | Motivo da mudança |
|---|---|---|---|
| postgresql | 600 MB | 512 MB | shared_buffers=128MB + 50 conns não justificam 600 MB |
| redis | 128 MB | 128 MB | — |
| minio | 300 MB | 256 MB | uso leve em prod (storage de imagens) |
| api | 512 MB | 512 MB | — |
| nginx *(novo)* | — | 64 MB | — |
| cadvisor *(obs)* | — | 128 MB | — |
| node-exporter *(obs)* | — | 64 MB | — |
| alloy *(obs, substitui promtail 64 MB)* | — | 128 MB | — |
| **Total de limites** | **1,604 MB** | **1,792 MB** | |

OS overhead: ~300 MB. Na prática os containers ficam bem abaixo dos limites (postgresql real ~300 MB, api real ~200 MB), então a margem é confortável. Se houver pressão, o próximo passo é t3.medium (4 GB, ~$15/mês a mais).

---

## Arquivos a Criar/Modificar

### Repo `api` — `docker-compose.prod.yml`

Adicionar serviços:

```yaml
# base (sempre ativo)
nginx:
  image: nginx:alpine
  ports: ["80:80"]
  volumes: [./nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro]
  depends_on: [api]
  mem_limit: 64m
  cpus: 0.25

# profile obs
cadvisor:
  image: gcr.io/cadvisor/cadvisor:latest
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - /sys:/sys:ro
    - /var/lib/docker:/var/lib/docker:ro
  mem_limit: 128m
  cpus: 0.25

node-exporter:
  image: prom/node-exporter:latest
  pid: host
  volumes:
    - /proc:/host/proc:ro
    - /sys:/host/sys:ro
    - /:/rootfs:ro
  command: [--path.procfs=/host/proc, --path.sysfs=/host/sys, --path.rootfs=/rootfs]
  mem_limit: 64m
  cpus: 0.1

alloy:                          # substitui promtail
  image: grafana/alloy:latest
  volumes:
    - ./alloy/alloy-prod.alloy:/etc/alloy/config.alloy:ro
    - ./logs:/var/log/oikos:ro
  env_file: [.env.prod]
  depends_on: [cadvisor, node-exporter]
  mem_limit: 128m
  cpus: 0.25
```

Remover o serviço `promtail` (substituído pelo `alloy`).
Ajustar limites: `postgresql` 600m→512m, `minio` 300m→256m.

### Repo `api` — `nginx/nginx.conf` *(novo)*

```nginx
server {
    listen 80;

    location / {
        proxy_pass         http://api:3333;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
}
```

### Repo `api` — `alloy/alloy-prod.alloy` *(novo)*

```alloy
// ── Logs (substitui promtail) ─────────────────────────────
local.file_match "oikos" {
  path_targets = [{ __path__ = "/var/log/oikos/*.log", job = "oikos-api" }]
}

loki.source.file "oikos" {
  targets    = local.file_match.oikos.targets
  forward_to = [loki.write.remote.receiver]
}

loki.write "remote" {
  endpoint { url = env("LOKI_URL") }
}

// ── Métricas de container (cAdvisor) ──────────────────────
prometheus.scrape "cadvisor" {
  targets         = [{ __address__ = "cadvisor:8080" }]
  scrape_interval = "15s"
  forward_to      = [prometheus.remote_write.monitoring.receiver]
}

// ── Métricas de host (node-exporter) ──────────────────────
prometheus.scrape "node_exporter" {
  targets         = [{ __address__ = "node-exporter:9100" }]
  scrape_interval = "15s"
  forward_to      = [prometheus.remote_write.monitoring.receiver]
}

// ── Remote Write ───────────────────────────────────────────
prometheus.remote_write "monitoring" {
  endpoint { url = env("PROMETHEUS_REMOTE_WRITE_URL") }
}
```

### Repo `api` — `.env.prod.example`

Adicionar variáveis:
```
PROMETHEUS_REMOTE_WRITE_URL=http://<monitoring-server-ip>:9090/api/v1/write
LOKI_URL=http://<monitoring-server-ip>:3100/loki/api/v1/push
```

### Repo `devops` — `observability/docker-compose.monitoring.yml` *(novo)*

Stack mínima para o servidor de monitoramento dedicado. Reusa imagens e configs já existentes no repo:

```yaml
# Roda no EC2 de monitoramento (t3.small recomendado)
# Não inclui OTel Collector, Tempo, Promtail ou Alertmanager
services:
  prometheus:
    image: prom/prometheus:v3.1.0
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --web.enable-remote-write-receiver   # recebe push da EC2 de prod
      - --storage.tsdb.retention.time=30d
      - --enable-feature=native-histograms
    volumes:
      - ./prometheus/prometheus-monitoring.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    ports: ["9090:9090"]
    mem_limit: 512m

  loki:
    image: grafana/loki:3.4.1
    volumes:
      - ./loki/loki-config.yml:/etc/loki/local-config.yaml:ro
      - loki_data:/loki
    ports: ["3100:3100"]
    mem_limit: 256m

  grafana:
    image: grafana/grafana:11.5.0
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/etc/grafana/dashboards:ro
      - grafana_data:/var/lib/grafana
    ports: ["3000:3000"]
    env_file: [.env.observability]
    mem_limit: 256m

volumes:
  prometheus_data:
  loki_data:
  grafana_data:
```

**Total no servidor de monitoramento: ~1,024 MB de limites** — cabe em t3.small com folga.

### Repo `devops` — `observability/prometheus/prometheus-monitoring.yml` *(novo)*

Config Prometheus simplificada para o servidor de monitoramento (só recebe remote_write, sem scrape ativo):

```yaml
global:
  scrape_interval: 15s

scrape_configs: []
```

### Repo `devops` — `observability/prometheus/prometheus.yml`

Adicionar jobs opcionais (úteis ao rodar testes de carga apontados para prod via SSH tunnel):
```yaml
- job_name: infra-cadvisor
  static_configs:
    - targets: ['${CADVISOR_HOST:-host.docker.internal}:8080']

- job_name: infra-node
  static_configs:
    - targets: ['${NODE_EXPORTER_HOST:-host.docker.internal}:9100']
```

### Repo `devops` — `observability/grafana/dashboards/infra-overview.json` *(novo)*

Dashboard **"Oikos — Infra Overview"** com 4 linhas de painéis, filtrado por `container_label_com_docker_compose_project="oikos-prod"`:

| Linha | Painéis | Métricas |
|---|---|---|
| Host | CPU total %, RAM usada %, Disco usado % | `node_cpu_seconds_total`, `node_memory_*`, `node_filesystem_*` |
| CPU por container | Timeseries multi-linha | `rate(container_cpu_usage_seconds_total[2m]) * 100` by service |
| RAM por container | Timeseries + % do limite | `container_memory_usage_bytes`, `container_spec_memory_limit_bytes` |
| Rede por container | RX/TX bytes/s | `rate(container_network_{receive,transmit}_bytes_total[2m])` by service |

### Repo `devops` — `observability/grafana/dashboards/infra-container.json` *(novo)*

Dashboard **"Oikos — Container Detail"** com variável `$service` (dropdown) populada via:
```
label_values(container_cpu_usage_seconds_total{
  container_label_com_docker_compose_project="oikos-prod"
}, container_label_com_docker_compose_service)
```

Painéis: CPU %, CPU throttling %, RAM usage vs limit, RAM working set vs cache, Network RX/TX, Disk I/O, restart count.

---

## Métricas-Chave nos Dashboards

| Métrica | Fonte | Uso |
|---|---|---|
| `container_cpu_usage_seconds_total` | cAdvisor | CPU % por container |
| `container_memory_usage_bytes` | cAdvisor | RAM usada |
| `container_spec_memory_limit_bytes` | cAdvisor | Limite de RAM (% de uso) |
| `container_network_receive_bytes_total` | cAdvisor | Tráfego RX |
| `container_network_transmit_bytes_total` | cAdvisor | Tráfego TX |
| `container_fs_reads_bytes_total` | cAdvisor | Leitura de disco |
| `container_fs_writes_bytes_total` | cAdvisor | Escrita de disco |
| `node_cpu_seconds_total` | node-exporter | CPU total do host |
| `node_memory_MemAvailable_bytes` | node-exporter | RAM disponível no EC2 |
| `node_filesystem_avail_bytes` | node-exporter | Espaço disponível em disco |

Label de serviço nos dashboards: `container_label_com_docker_compose_service` (gerado automaticamente pelo Docker Compose).

---

## Verificação

1. **EC2 prod:** `docker compose -f docker-compose.prod.yml --profile obs up -d`
2. `curl localhost:8080/metrics | grep container_cpu_usage` → cAdvisor respondendo
3. `curl localhost:9100/metrics | grep node_cpu` → node-exporter respondendo
4. `docker logs oikos-prod-alloy-1 2>&1 | grep -i "remote_write\|error"` → Alloy enviando sem erros
5. **Servidor de monitoramento:** `docker compose -f observability/docker-compose.monitoring.yml up -d`
6. No Grafana (porta 3000): Explore → datasource Prometheus → `container_cpu_usage_seconds_total` → séries com labels dos containers
7. Abrir `infra-overview.json` → todos os 5 serviços (nginx, api, postgresql, redis, minio) visíveis
8. Abrir `infra-container.json` → selecionar `api` no dropdown → painéis de detalhe com dados
