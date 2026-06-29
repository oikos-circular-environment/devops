# Oikos API — Load Tests (k6)

Testes de carga usando [k6](https://k6.io/). Todos os scripts fazem push de métricas para o Prometheus (via Remote Write), visíveis em tempo real no dashboard **Oikos API — k6 Load Tests** do Grafana.

## Pré-requisitos

- Docker instalado
- Stack de observabilidade rodando (`devops/observability/`) — para dashboards em tempo real
- API rodando em `localhost:3333`

## Scripts disponíveis

| Script | Carga | Duração | Objetivo |
|---|---|---|---|
| `smoke.js` | 2 VUs | 1 min | Sanity check pós-deploy — zero erros |
| `load.js` | 0→50 VUs | ~13 min | Carga realista com mix de tráfego |
| `stress.js` | 0→200 VUs | ~23 min | Encontrar ponto de ruptura |
| `spike.js` | 0→200 VUs instantâneo | ~5 min | Teste de surge abrupto |
| `soak.js` | 20 VUs | 70 min | Detectar memory leak e pool drain |

## Como executar

### Smoke (rápido, sem Prometheus)

```bash
docker run --rm --network=host \
  -e BASE_URL=http://localhost:3333 \
  -v "$(pwd)/devops/load-tests:/scripts" \
  grafana/k6:latest run /scripts/smoke.js
```

### Load / Stress / Spike (com Prometheus Remote Write)

```bash
docker run --rm --network=host \
  -e BASE_URL=http://localhost:3333 \
  -e TEST_USER_EMAIL=seu@email.com \
  -e TEST_USER_PASSWORD=suasenha \
  -e K6_PROMETHEUS_RW_SERVER_URL=http://localhost:9090/api/v1/write \
  -e K6_TEST_NAME=load \
  -v "$(pwd)/devops/load-tests:/scripts" \
  grafana/k6:latest run --out=experimental-prometheus-rw /scripts/load.js
```

Substitua `load.js` por `stress.js`, `spike.js` ou `soak.js` conforme o caso.

### Soak (requer credenciais)

```bash
docker run --rm --network=host \
  -e BASE_URL=http://localhost:3333 \
  -e TEST_USER_EMAIL=seu@email.com \
  -e TEST_USER_PASSWORD=suasenha \
  -e K6_PROMETHEUS_RW_SERVER_URL=http://localhost:9090/api/v1/write \
  -e K6_TEST_NAME=soak \
  -v "$(pwd)/devops/load-tests:/scripts" \
  grafana/k6:latest run --out=experimental-prometheus-rw /scripts/soak.js
```

## Variáveis de ambiente

| Variável | Obrigatória | Padrão | Descrição |
|---|---|---|---|
| `BASE_URL` | Não | `http://localhost:3333` | URL base da API |
| `TEST_USER_EMAIL` | Para scripts com auth | — | Email de usuário de teste |
| `TEST_USER_PASSWORD` | Para scripts com auth | — | Senha do usuário de teste |
| `K6_PROMETHEUS_RW_SERVER_URL` | Para dashboards | — | URL do Prometheus Remote Write |
| `K6_TEST_NAME` | Não | `oikos-load-test` | Label do teste no Grafana |

## Dashboard Grafana

Após iniciar um teste com `--out=experimental-prometheus-rw`, abra:
**http://localhost:3000/d/oikos-k6**

O dashboard atualiza a cada 5 segundos. Observe VUs, RPS, error rate e latência P95 em tempo real.

## Interpretando resultados

- **429 responses**: são esperados nos testes de stress e spike (rate-limiter intencional). Contados separadamente no counter `rate_limited_requests`, não computados como erros.
- **P95 > 2s**: indica gargalo. Verifique no dashboard "Oikos API — Overview" se é CPU, pg pool wait ou query lenta.
- **pg pool wait crescendo**: pool `max: 20` pode estar saturado. Considere aumentar.
- **Heap crescendo durante soak**: potencial memory leak.
