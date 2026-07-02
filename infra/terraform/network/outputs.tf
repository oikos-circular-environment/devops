output "subnet_id_public" {
  description = "OCID da subnet publica (VM A1.Flex)"
  value       = oci_core_subnet.public.id
}

output "subnet_id_private" {
  description = "OCID da subnet privada, sem IP publico, saida via NAT (VM E2.1.Micro)"
  value       = oci_core_subnet.private.id
}

output "vcn_id" {
  description = "OCID da VCN"
  value       = oci_core_vcn.this.id
}
