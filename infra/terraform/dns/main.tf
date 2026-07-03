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
