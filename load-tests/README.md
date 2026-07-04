# Oikos API — Load Tests (k6)

Testes de carga usando [k6](https://k6.io/). Todos os scripts fazem push de métricas para o Prometheus (via Remote Write), visíveis em tempo real no dashboard **Oikos API — k6 Load Tests** do Grafana.

## Pré-requisitos

- k6 instalado localmente (`k6 version` para verificar)
- Stack de observabilidade rodando (`devops/observability/`) — para dashboards em tempo real
- API rodando em `localhost:3333`

## Scripts disponíveis

| Script | Carga | Duração | Objetivo |
|---|---|---|---|
| `smoke.ts` | 2 VUs | 1 min | Sanity check pós-deploy — zero erros |
| `load.ts` | 0→50 VUs | ~13 min | Carga realista com mix de tráfego |
| `stress.ts` | 0→200 VUs | ~23 min | Encontrar ponto de ruptura |
| `spike.ts` | 0→200 VUs instantâneo | ~5 min | Teste de surge abrupto |
| `soak.ts` | 20 VUs | 70 min | Detectar memory leak e pool drain |

## Como executar

A partir da raiz do repositório `devops/`:

### Smoke (rápido, sem Prometheus)

```bash
npm run test:smoke
```

### Load / Stress / Spike / Soak (com Prometheus Remote Write)

```bash
npm run test:load
npm run test:stress
npm run test:spike
npm run test:soak
```

Os scripts com Prometheus fazem push de métricas usando native histograms (`K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=true`) e etiquetam a execução com `testid` para filtrar no Grafana.

O `K6_PROMETHEUS_RW_SERVER_URL` não precisa ser definido — o padrão do k6 (`http://localhost:9090/api/v1/write`) já aponta para o Prometheus da stack local.

## Variáveis de ambiente

| Variável | Padrão | Descrição |
|---|---|---|
| `BASE_URL` | `http://localhost:3333` | URL base da API |
| `K6_PROMETHEUS_RW_SERVER_URL` | `http://localhost:9090/api/v1/write` | Endpoint do Prometheus Remote Write |

## Dashboard Grafana

Após iniciar um teste com `--out=experimental-prometheus-rw`, abra:
**http://localhost:3000/d/oikos-k6**

O dashboard atualiza a cada 5 segundos. Observe VUs, RPS, error rate e latência P95 em tempo real.

## Timeline dos Testes (`suite.ts`)

Execução sequencial dos cinco cenários num único run:

| Cenário | Início | Duração | Termina em |
|---|---|---|---|
| smoke | 0s | 2m | ~2m10s |
| load | 2m30s | 13m | ~16m |
| stress | 16m30s | 23m | ~40m |
| spike | 40m30s | 5m30s | ~46m30s |
| soak | 47m | 40m | ~87m |

## Interpretando resultados

- **429 responses**: são esperados nos testes de stress e spike (rate-limiter intencional). Contados separadamente no counter `rate_limited_requests`, não computados como erros.
- **P95 > 2s**: indica gargalo. Verifique no dashboard "Oikos API — Overview" se é CPU, pg pool wait ou query lenta.
- **pg pool wait crescendo**: pool `max: 20` pode estar saturado. Considere aumentar.
- **Heap crescendo durante soak**: potencial memory leak.
