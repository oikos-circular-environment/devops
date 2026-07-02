variable "compartment_ocid" {
  type        = string
  description = "OCID do compartment onde as VMs sao criadas"
}

variable "subnet_id_public" {
  type        = string
  description = "OCID da subnet publica (vem do modulo network) - usada pela VM A1.Flex"
}

variable "subnet_id_private" {
  type        = string
  description = "OCID da subnet privada sem IP publico (vem do modulo network) - usada pela VM E2.1.Micro"
}
