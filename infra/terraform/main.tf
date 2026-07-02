locals {
  # Tenancy raiz sem sub-compartments criados ate agora - todos os recursos
  # sao provisionados direto no compartment raiz.
  compartment_ocid = var.tenancy_ocid
}

module "network" {
  source = "./network"

  compartment_ocid     = local.compartment_ocid
  cloudflare_api_token = var.cloudflare_api_token
}

module "compute" {
  source = "./compute"

  compartment_ocid = local.compartment_ocid
  subnet_id        = module.network.subnet_id
}
