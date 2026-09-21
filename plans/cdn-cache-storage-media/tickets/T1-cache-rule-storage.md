# T1 — Cache Rule pra mídia de `/storage/*`

**Status:** [ ] Pendente
**Depende de:** nada
**Módulos:** `infra/terraform/dns`, `docs/infrastructure.md`

## Contexto

A `api` do Oikos serve mídia (fotos/vídeos de denúncia, avatares) via
`GET /storage/*` — um proxy que faz stream do objeto do MinIO (ver
`api/src/modules/storage/storage-routes.ts`). Hoje `api.oikos.company` já
está atrás do Cloudflare (DNS proxied/orange-cloud, ver `infra/terraform/dns`),
mas nenhuma Cache Rule cacheia essas respostas na edge — toda requisição de
mídia, mesmo repetida, bate na VM `A1.Flex` (Always Free, recurso finito) e
no MinIO.

Cache Rules (`cloudflare_ruleset` na phase `http_request_cache_settings`) já
é o mesmo mecanismo usado hoje pra WAF em `infra/terraform/dns/security.tf`
(`cloudflare_ruleset` na phase `http_request_firewall_custom`) — mesmo
resource, phase diferente. Consistente com o padrão do projeto: tudo
Cloudflare é IaC (Terraform, provider `cloudflare/cloudflare`), nunca
dashboard manual.

**Cache busting já resolvido do lado da API** (`api`#chore/storage-cache-and-base64-cleanup):
avatares de perfil/empresa (paths fixos, sobrescritos a cada upload) agora
levam `?v=<timestamp>` na URL salva no banco — query string diferente vira
cache key diferente na edge, sem precisar de purge. Anexos de denúncia/resolução
já usavam path com timestamp (`complaints/{id}/{Date.now()}.ext`), nunca
colidem. **Esta Cache Rule pode ser aplicada sem esperar isso** (não há
dependência técnica), só está registrado aqui pra não reabrir a dúvida depois.

`mode = "override_origin"` foi escolhido de propósito: a API hoje não manda
`Cache-Control`/`ETag` no `GET /storage/*` (só `Content-Type`/`Content-Length`)
— com `override_origin` a Cloudflare cacheia mesmo sem esses headers de
origem. Se no futuro a API passar a mandar `Cache-Control` próprio, considerar
trocar pra `respect_origin` (fora de escopo deste ticket).

## O que fazer

Criar `infra/terraform/dns/cache.tf`:

```hcl
# Cache de midia em /storage - reduz carga na A1.Flex e latencia global
# (api serve via proxy do MinIO, sem CDN propria - ver docs/infrastructure.md)

resource "cloudflare_ruleset" "cache_storage_media" {
  zone_id     = local.zone_id
  name        = "Cache de midia em /storage"
  description = "Cacheia GET /storage/* na edge - TTL 30 dias, ignora ausencia de Cache-Control na origem"
  phase       = "http_request_cache_settings"
  kind        = "zone"

  rules = [
    {
      description = "Cache eligible para storage"
      expression  = "(http.host eq \"api.${var.domain_name}\") and starts_with(http.request.uri.path, \"/storage/\")"
      action      = "set_cache_settings"
      action_parameters = {
        cache = true
        edge_ttl = {
          mode    = "override_origin"
          default = 2592000 # 30 dias
        }
        browser_ttl = {
          mode    = "override_origin"
          default = 2592000 # 30 dias
        }
      }
    }
  ]
}
```

Ajustar nomes/valores se `terraform plan` acusar schema diferente do
esperado (provider pode ter mudado desde a redação deste ticket — conferir
com `terraform providers` a versão do `cloudflare/cloudflare` em uso antes
de aplicar cegamente o HCL acima).

Atualizar `docs/infrastructure.md`, seção `## Cloudflare`: acrescentar um
bullet dizendo que Cache Rules fazem parte do Free plan (10 regras grátis,
usamos 1) e continuam em `$0/mês` — mesmo padrão dos outros bullets dessa
seção.

## Checklist

- [ ] Criar `infra/terraform/dns/cache.tf` com o `cloudflare_ruleset` acima
- [ ] `terraform fmt` no diretório `infra/terraform`
- [ ] `terraform validate` (dentro de `infra/terraform`, com providers já inicializados — `terraform init` se necessário)
- [ ] `terraform plan` — conferir que o plan só **adiciona** 1 resource (`cloudflare_ruleset.cache_storage_media`), não recria/altera nada existente
- [ ] Atualizar `docs/infrastructure.md` (seção Cloudflare) com o bullet de Cache Rules
- [ ] Abrir PR pra `development` (nunca commit direto — guard do lefthook bloqueia mesmo assim)
- [ ] Confirmar no Terraform Cloud (workspace do projeto) se o `apply` real dispara no merge pra `development` ou só pra `production` — **não presumir**, esse repo tem histórico de mudar isso; anotar a resposta na descrição do PR
- [ ] Depois do apply real: bater `curl -sI https://api.oikos.company/storage/<algum-arquivo-existente>` duas vezes e conferir o header `cf-cache-status` (`MISS` na primeira, `HIT` na segunda)

## Fora de escopo (não fazer aqui)

- Mudar `storage-routes.ts` da `api` pra mandar `Cache-Control`/`ETag` de
  origem — não é necessário com `override_origin`, e é mudança em outro repo.
- Cloudflare Cache Reserve (plano pago) — sem necessidade no volume atual.
- Migrar MinIO pra Cloudflare R2 — mudança de infra maior, não é sobre CDN/cache, é sobre onde os bytes moram.
