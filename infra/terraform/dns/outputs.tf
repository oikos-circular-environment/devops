output "zone_id" {
  description = "Zone ID do dominio no Cloudflare"
  value       = local.zone_id
}

output "origin_certificate_pem" {
  description = "Certificado Origin CA assinado - copiar manualmente pro GitHub Secret CLOUDFLARE_ORIGIN_CERT (T9). Ver com: terraform output -raw origin_certificate_pem"
  value       = cloudflare_origin_ca_certificate.this.certificate
  sensitive   = true
}

output "origin_private_key_pem" {
  description = "Chave privada do certificado Origin CA - copiar manualmente pro GitHub Secret CLOUDFLARE_ORIGIN_KEY (T9). Ver com: terraform output -raw origin_private_key_pem"
  value       = tls_private_key.origin.private_key_pem
  sensitive   = true
}
