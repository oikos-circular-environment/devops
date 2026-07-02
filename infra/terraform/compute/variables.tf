variable "compartment_ocid" {
  type        = string
  description = "OCID do compartment onde as VMs sao criadas"
}

variable "subnet_id" {
  type        = string
  description = "OCID da subnet compartilhada (vem do modulo network)"
}
