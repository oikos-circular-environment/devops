output "app_public_ip" {
  description = "IP publico da VM A1.Flex"
  value       = oci_core_instance.app.public_ip
}

output "app_private_ip" {
  description = "IP privado da VM A1.Flex"
  value       = oci_core_instance.app.private_ip
}

output "observability_private_ip" {
  description = "IP privado da VM E2.1.Micro (sem IP publico)"
  value       = oci_core_instance.observability.private_ip
}
