output "subnet_id" {
  description = "OCID da subnet compartilhada pelas duas VMs"
  value       = oci_core_subnet.this.id
}

output "vcn_id" {
  description = "OCID da VCN"
  value       = oci_core_vcn.this.id
}
