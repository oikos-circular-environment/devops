resource "cloudflare_ruleset" "require_client_key" {
  zone_id     = local.zone_id
  name        = "Exige X-Client-Key na api"
  description = "Bloqueia na edge requisicoes para api.oikos.company sem o header X-Client-Key (mobile#34)"
  phase       = "http_request_firewall_custom"
  kind        = "zone"

  rules = [
    {
      description = "Bloqueia sem X-Client-Key"
      expression  = "(http.host eq \"api.${var.domain_name}\") and (http.request.headers[\"x-client-key\"][0] eq \"\")"
      action      = "block"
    }
  ]
}

resource "cloudflare_bot_management" "this" {
  zone_id    = local.zone_id
  fight_mode = true
  enable_js  = true
}

resource "cloudflare_turnstile_widget" "support_form" {
  account_id = var.cloudflare_account_id
  name       = "${var.domain_name} - formulario de suporte"
  domains    = [var.domain_name, "www.${var.domain_name}"]
  mode       = "managed"
}
