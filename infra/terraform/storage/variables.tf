variable "compartment_ocid" {
  type        = string
  description = "OCID do compartment onde o bucket e as policies sao criados"
}

variable "tenancy_ocid" {
  type        = string
  description = "OCID da tenancy - dynamic groups e policies de identidade sao sempre criados no nivel da tenancy na OCI, independente do compartment dos recursos que eles protegem"
}

variable "app_instance_id" {
  type        = string
  description = "OCID da instancia A1.Flex - unica autorizada (via instance principal) a escrever/ler no bucket de backup"
}
