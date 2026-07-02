variable "tenancy_ocid" {
  type        = string
  description = "OCID da tenancy OCI"
  sensitive   = true
}

variable "user_ocid" {
  type        = string
  description = "OCID do usuario OCI usado pela API key do Terraform"
  sensitive   = true
}

variable "fingerprint" {
  type        = string
  description = "Fingerprint da API key OCI registrada no usuario acima"
  sensitive   = true
}

variable "private_key" {
  type        = string
  description = "Chave privada (PEM) da API key OCI"
  sensitive   = true
}

variable "region" {
  type        = string
  description = "Regiao OCI (home region da tenancy)"
  default     = "sa-vinhedo-1"
}

variable "cloudflare_api_token" {
  type        = string
  description = "Account API Token da Cloudflare. Usado aqui so pra ler os IP ranges oficiais na Security List; registros DNS e zona ficam a cargo da ticket T5"
  sensitive   = true
}

variable "cloudflare_account_id" {
  type        = string
  description = "Account ID da Cloudflare. Nao usado ainda pelo T4 - declarado so pra silenciar o warning de variavel nao declarada, sera consumido a partir da ticket T5 (DNS)"
  sensitive   = true
  default     = null
}
