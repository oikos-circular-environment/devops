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

# --- Certificado Cloudflare Origin CA (usado pelo nginx na T6) ---
# Chave privada e CSR gerados dentro do proprio Terraform (provider tls) -
# nunca sai da maquina/state gerenciado, e o certificado assinado volta via
# API da Cloudflare. Os valores finais (cert + chave) precisam ser copiados
# manualmente pro GitHub Secrets do repo (CLOUDFLARE_ORIGIN_CERT/
# CLOUDFLARE_ORIGIN_KEY) - o assistente nao automatiza esse cadastro,
# consistente com a regra de nunca manipular valor de secret.

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
    # A API da Cloudflare nao garante a mesma ordem de "hostnames" no
    # retorno - sem isso, todo plan detecta uma "mudanca" (so a ordem)
    # e forca recriar o certificado (hostnames e ForceNew nesse recurso).
    ignore_changes = [hostnames]
  }
}

# --- Configuracoes de seguranca da zona (achado em auditoria via API, 2026-07-03) ---
# Provider v5 usa um resource por configuracao (cloudflare_zone_setting),
# substituiu o cloudflare_zone_settings_override monolitico da v4.

resource "cloudflare_zone_setting" "ssl_strict" {
  zone_id    = local.zone_id
  setting_id = "ssl"
  value      = "strict"
  # Zona estava em "full" - aceita qualquer certificado na origem sem validar,
  # mesmo com o Origin CA (acima) ja emitido especificamente pra permitir
  # validacao estrita. "strict" fecha esse gap de verdade.
}

resource "cloudflare_zone_setting" "min_tls_1_2" {
  zone_id    = local.zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
  # Zona estava em "1.0" - TLS 1.0/1.1 sao considerados obsoletos/inseguros
  # (BEAST/POODLE, fora de conformidade PCI-DSS desde 2018). TLS 1.3 ja
  # estava habilitado (tls_1_3 setting, nao gerenciado aqui - default "on").
}

resource "cloudflare_zone_setting" "force_https" {
  zone_id    = local.zone_id
  setting_id = "always_use_https"
  value      = "on"
  # Zona estava em "off" - requisicao HTTP pura nao redirecionava sozinha
  # pra HTTPS.
}

# Import blocks pra esses 3 resources ficam no main.tf da raiz (nao aqui) -
# import block dentro de modulo filho nao e suportado, precisa do caminho
# completo com "module.dns." no "to" (ver infra/terraform/main.tf).
