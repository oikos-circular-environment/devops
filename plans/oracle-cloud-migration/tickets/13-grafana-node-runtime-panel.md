# Ticket 13 — Painel Grafana de runtime Node.js (GC / event loop)

**Status**: Implementado (2026-07-07) — `observability/grafana/dashboards/node-runtime.json`. Nomes reais confirmados direto no Prometheus de produção antes de escrever o JSON (label `job`, não `service_name` — ver nota abaixo); labels de atributo confirmados como `v8js_gc_type`, `v8js_heap_space_name`, `v8js_resource_type`.

## Contexto

`api` e `web` agora emitem métricas de runtime do Node/V8 via `@opentelemetry/instrumentation-runtime-node` (ver PRs de instrumentação em `api`/`web`), exportadas pro Alloy junto com o resto do OTLP já existente. O objetivo é conseguir responder, na próxima vez que aparecer um pico de CPU no dashboard "Container Detail" (`infra-container.json`), se ele veio de GC, de bloqueio do event loop, ou de tráfego real — hoje esse dashboard só mostra o sintoma (cgroup/cAdvisor), nunca a causa dentro do runtime.

Métricas esperadas (nomes OTel, antes da tradução do exporter Prometheus do Alloy):

- `nodejs.eventloop.utilization` (gauge, unit `1`)
- `nodejs.eventloop.delay.{mean,max,min,stddev,p50,p90,p99}` (gauge, unit `s`)
- `v8js.gc.duration` (histogram, unit `s`, atributo `v8js.gc.type`)
- `v8js.memory.heap.used` / `v8js.memory.heap.limit` (gauge, unit `By`, atributo `v8js.heap.space.name`)
- `v8js.resource.active` (gauge, unit `{resource}`, atributo `v8js.resource.type`)

## Por que não foi feito junto

Os nomes acima já saem traduzidos pelo `otelcol.exporter.prometheus` do Alloy (pontos → underscore, sufixo de unidade tipo `_seconds`/`_bytes`), e a tradução exata do OTel Collector pra unidades incomuns (`1`, `{resource}`) não é 100% previsível sem inspecionar o Prometheus real — “adivinhar” esses nomes no JSON do dashboard arrisca subir um painel com query errada e “No data”, o mesmo problema de observabilidade que motivou este ticket.

## O que fazer

1. Depois do deploy de `api`/`web` com a instrumentação nova, rodar contra o Prometheus da `E2.1.Micro` (via túnel SSH bastion, ver `docs/infrastructure.md`):
   ```
   curl -s 'http://10.0.2.37:9090/api/v1/label/__name__/values' | grep -E 'nodejs_eventloop|v8js_'
   ```
2. Confirmar os nomes reais (com sufixo de unidade) e os labels disponíveis (`service_name` deve distinguir `oikos-api`/`oikos-web`).
3. Criar `observability/grafana/dashboards/node-runtime.json` — dashboard novo (não estender `infra-container.json`, que é cAdvisor/cgroup, escopo diferente), com variável `$service` (`oikos-api`/`oikos-web`, mesmo padrão de `infra-container.json`) e painéis:
   - Event Loop Utilization (%) — `nodejs_eventloop_utilization`
   - Event Loop Delay (mean/p99) — `nodejs_eventloop_delay_*`
   - GC Duration por tipo (rate) — `v8js_gc_duration_*`
   - Heap usado vs limite por heap space — `v8js_memory_heap_*`
4. Registrar o dashboard no provisioning do Grafana (mesmo mecanismo dos outros arquivos em `observability/grafana/dashboards/`).
