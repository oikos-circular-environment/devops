data "oci_identity_availability_domains" "this" {
  compartment_id = var.compartment_ocid
}

locals {
  availability_domain   = data.oci_identity_availability_domains.this.availability_domains[0].name
  deploy_ssh_public_key = file("${path.module}/files/deploy_id.pub")
}

# Shape filtra a arquitetura automaticamente (A1.Flex = ARM, E2.1.Micro = x86),
# entao as duas data sources abaixo ja retornam so imagens compativeis.
# Variante "Minimal" (menos pacotes pre-instalados, equivalente a uma imagem
# Docker slim) em vez da imagem padrao - reduz baseline de RAM/disco, o que
# importa principalmente na E2.1.Micro (1GB, orcamento de memoria apertado).
data "oci_core_images" "app" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04 Minimal aarch64"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

data "oci_core_images" "observability" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04 Minimal"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "app" {
  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain
  display_name        = "oikos-app"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = true
    hostname_label   = "oikos-app"
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.app.images[0].id
    boot_volume_size_in_gbs = 150
  }

  metadata = {
    ssh_authorized_keys = local.deploy_ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init/init.yaml.tftpl", {
      ssh_public_key = local.deploy_ssh_public_key
      swap_size_gb   = 0
    }))
  }
}

resource "oci_core_instance" "observability" {
  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain
  display_name        = "oikos-observability"
  shape               = "VM.Standard.E2.1.Micro"

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = false
    hostname_label   = "oikos-observability"
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.observability.images[0].id
    boot_volume_size_in_gbs = 50
  }

  metadata = {
    ssh_authorized_keys = local.deploy_ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init/init.yaml.tftpl", {
      ssh_public_key = local.deploy_ssh_public_key
      swap_size_gb   = 9
    }))
  }
}
