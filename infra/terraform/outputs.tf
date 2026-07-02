output "app_public_ip" {
  description = "IP publico da VM A1.Flex (api + web + nginx)"
  value       = module.compute.app_public_ip
}

output "app_private_ip" {
  description = "IP privado da VM A1.Flex, usado pela E2.1.Micro pra enviar metricas/logs/traces"
  value       = module.compute.app_private_ip
}

output "observability_private_ip" {
  description = "IP privado da VM E2.1.Micro (sem IP publico, so alcancavel pela A1.Flex)"
  value       = module.compute.observability_private_ip
}

output "cloudflare_zone_id" {
  description = "Zone ID do dominio no Cloudflare"
  value       = module.dns.zone_id
}

output "origin_certificate_pem" {
  description = "Certificado Origin CA - copiar manualmente pro GitHub Secret CLOUDFLARE_ORIGIN_CERT. Ver com: terraform output -raw origin_certificate_pem"
  value       = module.dns.origin_certificate_pem
  sensitive   = true
}

output "origin_private_key_pem" {
  description = "Chave privada do certificado Origin CA - copiar manualmente pro GitHub Secret CLOUDFLARE_ORIGIN_KEY. Ver com: terraform output -raw origin_private_key_pem"
  value       = module.dns.origin_private_key_pem
  sensitive   = true
}

output "backup_bucket_name" {
  description = "Nome do bucket de backup no Object Storage"
  value       = module.storage.bucket_name
}

output "backup_namespace" {
  description = "Namespace do Object Storage - os scripts de backup usam isso pra montar a URL do bucket"
  value       = module.storage.namespace
}
