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
