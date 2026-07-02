variable "cloudflare_account_id" {
  type        = string
  description = "Account ID da Cloudflare"
  sensitive   = true
}

variable "domain_name" {
  type        = string
  description = "Dominio raiz gerenciado no Cloudflare"
}

variable "app_public_ip" {
  type        = string
  description = "IP publico da VM A1.Flex (vem do modulo compute) - destino dos 4 registros DNS"
}

variable "developer_email" {
  type        = string
  description = "E-mail autorizado pelo Cloudflare Access a acessar grafana/minio (1 usuario - o desenvolvedor)"
  default     = "christiancnp@gmail.com"
}
