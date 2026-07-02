resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "oikos-vcn"
  dns_label      = "oikosvcn"
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "oikos-igw"
  enabled        = true
}

# Necessario pra E2.1.Micro (sem IP publico) ter saida pra internet - um
# Internet Gateway sozinho so roteia trafego de instancia com IP publico.
# Sem isso, cloud-init nao consegue nem instalar o Docker (apt sem rota).
resource "oci_core_nat_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "oikos-nat"
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "oikos-route-table-public"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "oikos-route-table-private"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this.id
  }
}

# Ranges oficiais da Cloudflare - fonte usada pela Security List abaixo pra
# liberar a 443 so pro trafego que passa pelo proxy da Cloudflare.
data "cloudflare_ip_ranges" "this" {}

resource "oci_core_security_list" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "oikos-security-list"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # So IPv4 - a VCN nao tem IPv6 habilitado e as instancias so recebem IP
  # publico IPv4, entao regras IPv6 aqui seriam config morta (OCI rejeita a
  # criacao da Security List se a VCN nao suportar o CIDR IPv6 referenciado).
  dynamic "ingress_security_rules" {
    for_each = data.cloudflare_ip_ranges.this.ipv4_cidrs
    content {
      protocol    = "6" # TCP
      source      = ingress_security_rules.value
      description = "HTTPS via Cloudflare (IPv4)"

      tcp_options {
        min = 443
        max = 443
      }
    }
  }

  # SSH aberto pra qualquer IP - decisao consciente (projeto solo, sem
  # bastion dedicado, IP residencial dinamico). Hardening fica por conta do
  # cloud-init: autenticacao so por chave, sem senha, sem login root.
  # Na subnet privada essa regra e inofensiva - sem IP publico, nao ha como
  # a internet alcancar a porta de qualquer forma.
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    description = "SSH (usuario deploy, autenticacao so por chave)"

    tcp_options {
      min = 22
      max = 22
    }
  }
}

# Subnet publica - so a A1.Flex, unica com IP publico e porta 443 exposta.
resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = "10.0.1.0/24"
  display_name               = "oikos-subnet-public"
  dns_label                  = "oikospub"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.this.id]
  prohibit_public_ip_on_vnic = false
}

# Subnet privada - so a E2.1.Micro. IP publico proibido no nivel da subnet
# (nao so "nao atribuido") e saida pra internet via NAT Gateway.
resource "oci_core_subnet" "private" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = "10.0.2.0/24"
  display_name               = "oikos-subnet-private"
  dns_label                  = "oikospriv"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.this.id]
  prohibit_public_ip_on_vnic = true
}
