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
  description = "Account API Token da Cloudflare. Usado na Security List (T4, ler IP ranges) e no modulo dns (T5, registros/Access/certificado)"
  sensitive   = true
}

variable "cloudflare_account_id" {
  type        = string
  description = "Account ID da Cloudflare. Usado pelo modulo dns (T5) pra localizar a zona e criar as aplicacoes de Access"
  sensitive   = true
}

variable "domain_name" {
  type        = string
  description = "Dominio raiz gerenciado no Cloudflare"
  default     = "oikos.company"
}
