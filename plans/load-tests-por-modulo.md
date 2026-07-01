# Plano: Reorganização dos testes de carga por módulo/domínio

## Contexto

Os testes de carga atuais estão organizados por **tipo de teste** (smoke, load, stress, spike, soak), não por módulo de domínio. Isso significa que cada arquivo mistura múltiplos endpoints e não reflete a realidade de uso de cada funcionalidade.

O guia do k6 recomenda partir de testes isolados em componentes individuais e, conforme a estratégia amadurece, aplicar tipos de teste adequados ao padrão de uso real de cada módulo.

O objetivo é reorganizar por **módulo/domínio** e aplicar apenas os tipos de teste que fazem sentido para cada contexto — por exemplo, listagem de market e criação de complaints merecem suite completa, enquanto dados de referência (waste-categories) precisam apenas de smoke + load.

---

## Rate Limit como variável de calibração

A API possui rate limiting. Isso tem implicações diretas na estratégia de testes:

- **Load e Soak tests** devem ser calibrados para operar *dentro* do rate limit — o objetivo é validar performance sob carga esperada, não saturar o limitador. Ao calibrar os VUs/RPS abaixo do teto do rate limit, garantimos consumo ótimo dos recursos e resultados representativos.
- **Stress e Spike tests** são intencionalmente projetados para ultrapassar o rate limit — isso é valioso porque expõe os limites reais da API, pontos de saturação e oportunidades de melhoria (ex: se muitas requisições chegam como 429, o bottleneck pode estar no rate limiter em si, não na lógica de negócio).
- O helper `checkOk` já trata 429 como non-error, contando via `rate_limited_requests` counter — isso está correto e deve ser mantido.

**Prática recomendada:** parametrizar o rate limit via `.env.k6` (ex: `RATE_LIMIT_RPS=50`) e usar esse valor para calcular os VUs nos testes de load/soak, garantindo que os testes de média carga fiquem sistematicamente abaixo do teto. Stress/spike ficam livres para exceder.

---

## Estrutura nova

```
load-tests/
  config/
    base-options.ts           ← sem alterações
  helpers/
    auth.ts                   ← sem alterações
    checks.ts                 ← sem alterações
    complaint-data.ts         ← sem alterações
  modules/
    health/
      smoke.ts                ← GET /health, 1-2 VUs, 1 min
    waste-categories/
      smoke.ts                ← verifica lista não-vazia
      load.ts                 ← carga moderada em dados de referência
    market/
      flows.ts                ← funções de cenário exportadas
      smoke.ts
      load.ts
      stress.ts
      spike.ts
      soak.ts
      suite.ts                ← orquestra todos os tipos do módulo
    complaints/
      flows.ts                ← funções de cenário exportadas
      smoke.ts
      load.ts
      stress.ts
      spike.ts
      soak.ts
      suite.ts                ← orquestra todos os tipos do módulo
  suite.ts                    ← orquestrador global (market + complaints)
  README.md                   ← atualizado
```

### Arquivos removidos
- `load-tests/smoke.ts`, `load.ts`, `stress.ts`, `spike.ts`, `soak.ts` (nível raiz)

---

## Matriz de tipos de teste por módulo

| Módulo | smoke | load | stress | spike | soak | Justificativa |
|--------|-------|------|--------|-------|------|---------------|
| health | ✓ | — | — | — | — | Verificação de infra apenas |
| waste-categories | ✓ | ✓ | — | — | — | Dados de referência, read-only, baixo volume |
| market | ✓ | ✓ | ✓ | ✓ | ✓ | Query geo-espacial de alta frequência, feature core |
| complaints | ✓ | ✓ | ✓ | ✓ | ✓ | Feature principal, escrita + leitura + mapa |

> **Padrão extensível:** quando novos módulos surgirem (ex: cadastro de empresa), aplicar a mesma lógica — fluxos de baixo volume recebem apenas smoke + load.

---

## Padrão de implementação

### `flows.ts` em cada módulo

Cada módulo exporta funções de cenário para reutilização entre os tipos de teste:

```typescript
// modules/market/flows.ts
export function marketPublicFlow(): void { /* GET /v1/market */ }
```

### Arquivos de tipo de teste (ex: `market/load.ts`)

Cada arquivo apenas configura as opções e importa o flow:

```typescript
import { makeOptions } from "../../config/base-options.ts";
import { marketPublicFlow } from "./flows.ts";

export const options = makeOptions([
  { duration: "2m", target: 10 },
  { duration: "4m", target: 50 },
  { duration: "2m", target: 0 },
]);

export default function(): void { marketPublicFlow(); }
```

### `suite.ts` dentro de cada módulo

Usa múltiplos `scenarios` com `startTime` (mesmo padrão do `suite.ts` atual) para rodar todos os tipos em sequência numa única execução k6.

---

## Endpoints por módulo

**market/flows.ts:**
- `GET /v1/market?lat=...&lon=...&radius=...`

**complaints/flows.ts:**
- `GET /v1/complaints/map?lat=...&lon=...&radius=...` (público)
- `GET /v1/complaints` (autenticado)
- `POST /v1/complaints` (autenticado)

**Setup de auth:** `registerUser` + `getToken` de `helpers/auth.ts` — reutilizados sem alteração.

---

## Scripts `package.json`

Substituir os scripts por tipo por scripts por módulo:

```json
"test:health":            "dotenv -e load-tests/.env.k6 -- k6 run load-tests/modules/health/smoke.ts",
"test:waste-categories":  "dotenv -e load-tests/.env.k6 -- k6 run -o experimental-prometheus-rw load-tests/modules/waste-categories/suite.ts",
"test:market":            "dotenv -e load-tests/.env.k6 -- k6 run -o experimental-prometheus-rw load-tests/modules/market/suite.ts",
"test:complaints":        "dotenv -e load-tests/.env.k6 -- k6 run -o experimental-prometheus-rw load-tests/modules/complaints/suite.ts",
"test:k6":                "dotenv -e load-tests/.env.k6 -- k6 run -o experimental-prometheus-rw load-tests/suite.ts"
```

> Os scripts antigos (`test:smoke`, `test:load`, etc.) são removidos.

---

## Verificação

1. `npm run test:health` → passa em < 1 min com 1-2 VUs
2. `npm run test:waste-categories` → smoke + load sem erros
3. `npm run test:market` → suite completa de market (smoke → load → stress → spike → soak)
4. `npm run test:complaints` → suite completa de complaints
5. `npm run test:k6` → orquestrador global, valida módulos críticos em sequência
6. Conferir no Grafana: `http_req_duration`, `http_req_failed`, `rate_limited_requests` (observar distribuição de 429 nos testes de stress/spike vs ausência nos de load/soak)
