variable "compartment_ocid" {
  type        = string
  description = "OCID do compartment onde a rede e criada"
}

variable "cloudflare_api_token" {
  type        = string
  description = "Token usado so pra autenticar a leitura dos IP ranges da Cloudflare (data source cloudflare_ip_ranges)"
  sensitive   = true
}
