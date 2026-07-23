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

output "turnstile_sitekey" {
  description = "Site key do widget Turnstile (publica) - vai pro frontend web (web#32)"
  value       = cloudflare_turnstile_widget.support_form.sitekey
}

output "turnstile_secret" {
  description = "Secret key do widget Turnstile - copiar manualmente pro GitHub Secret TURNSTILE_SECRET_KEY (validacao no api#50 / web#32). Ver com: terraform output -raw turnstile_secret"
  value       = cloudflare_turnstile_widget.support_form.secret
  sensitive   = true
}
