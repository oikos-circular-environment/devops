data "cloudflare_zones" "this" {
  name = var.domain_name
  account = {
    id = var.cloudflare_account_id
  }
}

locals {
  zone_id = data.cloudflare_zones.this.result[0].id
}

# --- Registros DNS proxied (todos apontam pra VM A1.Flex - unica com IP publico) ---

resource "cloudflare_dns_record" "api" {
  zone_id = local.zone_id
  name    = "api"
  type    = "A"
  content = var.app_public_ip
  ttl     = 1 # "automatic" - obrigatorio quando proxied = true
  proxied = true
  comment = "api - VM A1.Flex, gerenciado pelo Terraform (T5)"
}

resource "cloudflare_dns_record" "apex" {
  zone_id = local.zone_id
  name    = "@"
  type    = "A"
  content = var.app_public_ip
  ttl     = 1
  proxied = true
  comment = "web (apex) - VM A1.Flex, gerenciado pelo Terraform (T5)"
}

resource "cloudflare_dns_record" "www" {
  zone_id = local.zone_id
  name    = "www"
  type    = "CNAME"
  content = var.domain_name
  ttl     = 1
  proxied = true
  comment = "web (www) - aponta pro apex, mesmo frontend na VM A1.Flex, gerenciado pelo Terraform (T5)"
}

resource "cloudflare_dns_record" "grafana" {
  zone_id = local.zone_id
  name    = "grafana"
  type    = "A"
  content = var.app_public_ip
  ttl     = 1
  proxied = true
  comment = "grafana - protegido pelo login proprio do Grafana (usuario/senha forte)"
}

resource "cloudflare_dns_record" "minio" {
  zone_id = local.zone_id
  name    = "minio"
  type    = "A"
  content = var.app_public_ip
  ttl     = 1
  proxied = true
  comment = "console do minio - protegido pelo login proprio do MinIO (usuario/senha forte)"
}

# Certificado Cloudflare Origin CA - ver docs/infrastructure.md (Cloudflare, ticket 06)

resource "tls_private_key" "origin" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "origin" {
  private_key_pem = tls_private_key.origin.private_key_pem

  subject {
    common_name  = var.domain_name
    organization = "Oikos"
  }

  dns_names = [
    var.domain_name,
    "*.${var.domain_name}",
  ]
}

resource "cloudflare_origin_ca_certificate" "this" {
  csr                = tls_cert_request.origin.cert_request_pem
  hostnames          = [var.domain_name, "*.${var.domain_name}"]
  request_type       = "origin-rsa"
  requested_validity = 5475 # 15 anos - o maximo permitido

  lifecycle {
    ignore_changes = [hostnames] # ordem de hostnames nao e garantida pela API - ver docs/infrastructure.md (Cloudflare)
  }
}

# Configuracoes de seguranca da zona - ver docs/infrastructure.md (Cloudflare)

resource "cloudflare_zone_setting" "ssl_strict" {
  zone_id    = local.zone_id
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_zone_setting" "min_tls_1_2" {
  zone_id    = local.zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
}

resource "cloudflare_zone_setting" "force_https" {
  zone_id    = local.zone_id
  setting_id = "always_use_https"
  value      = "on"
}

# Import blocks pra esses 3 resources ficam no main.tf da raiz - ver docs/infrastructure.md (Cloudflare)
