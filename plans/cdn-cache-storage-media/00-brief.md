# Cache CDN pra mídia de `/storage/*`

## Contexto

Discussão em sessão com o `api`: a rota `GET /storage/*` (proxy do MinIO)
está atrás do Cloudflare (DNS proxied) mas sem nenhuma Cache Rule — cada
request de mídia bate na origin. Detalhes, decisões e o HCL exato estão no
ticket único abaixo.

## Tickets

1. [T1 — Cache Rule pra mídia de `/storage/*`](./tickets/T1-cache-rule-storage.md)
