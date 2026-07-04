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

  compartment_ocid  = local.compartment_ocid
  subnet_id_public  = module.network.subnet_id_public
  subnet_id_private = module.network.subnet_id_private
}

module "dns" {
  source = "./dns"

  cloudflare_account_id = var.cloudflare_account_id
  domain_name           = var.domain_name
  app_public_ip         = module.compute.app_public_ip
}

module "storage" {
  source = "./storage"

  compartment_ocid = local.compartment_ocid
  tenancy_ocid     = var.tenancy_ocid
  app_instance_id  = module.compute.app_instance_id
}

# Import dos cloudflare_zone_setting do module.dns - ver docs/infrastructure.md (Cloudflare)
import {
  to = module.dns.cloudflare_zone_setting.ssl_strict
  id = "${module.dns.zone_id}/ssl"
}

import {
  to = module.dns.cloudflare_zone_setting.min_tls_1_2
  id = "${module.dns.zone_id}/min_tls_version"
}

import {
  to = module.dns.cloudflare_zone_setting.force_https
  id = "${module.dns.zone_id}/always_use_https"
}
