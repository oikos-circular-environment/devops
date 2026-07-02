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
