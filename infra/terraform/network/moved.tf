# Preserva a identidade dos recursos renomeados no refactor de subnet unica
# -> subnet publica/privada, pra Terraform tratar como update in-place em vez
# de destroy+create (a subnet "this" original tem a VM oikos-app anexada).
moved {
  from = oci_core_subnet.this
  to   = oci_core_subnet.public
}

moved {
  from = oci_core_route_table.this
  to   = oci_core_route_table.public
}
