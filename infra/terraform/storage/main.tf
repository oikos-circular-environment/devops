data "oci_objectstorage_namespace" "this" {
  compartment_id = var.compartment_ocid
}

resource "oci_objectstorage_bucket" "backups" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = "oikos-backups"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  versioning     = "Disabled"
}

# Retencao de 7 dias por prefixo, nativa da OCI - sem script customizado de
# rotacao/limpeza (T8, decisao do tech-plan).
resource "oci_objectstorage_object_lifecycle_policy" "backups" {
  namespace = data.oci_objectstorage_namespace.this.namespace
  bucket    = oci_objectstorage_bucket.backups.name

  rules {
    name        = "expire-postgres-7d"
    action      = "DELETE"
    time_amount = 7
    time_unit   = "DAYS"
    is_enabled  = true
    target      = "objects"

    object_name_filter {
      inclusion_prefixes = ["postgres/"]
    }
  }

  rules {
    name        = "expire-redis-7d"
    action      = "DELETE"
    time_amount = 7
    time_unit   = "DAYS"
    is_enabled  = true
    target      = "objects"

    object_name_filter {
      inclusion_prefixes = ["redis/"]
    }
  }
}

# Instance Principal - a A1.Flex se autentica no Object Storage sem nenhuma
# credencial estatica embutida na VM (nem API key, nem token). A OCI emite um
# certificado efemero automaticamente pra instancia; o dynamic group abaixo
# reconhece essa instancia especifica pelo OCID, e a policy da a ela permissao
# de gerenciar objetos so nesse bucket. Os scripts de backup (backup-postgres.sh
# /backup-redis.sh) usam `oci ... --auth instance_principal`.
resource "oci_identity_dynamic_group" "backup" {
  compartment_id = var.tenancy_ocid
  name           = "oikos-backup-dynamic-group"
  description    = "VM A1.Flex - autorizada a escrever backups no bucket oikos-backups via instance principal"
  matching_rule  = "instance.id = '${var.app_instance_id}'"
}

resource "oci_identity_policy" "backup" {
  compartment_id = var.compartment_ocid
  name           = "oikos-backup-policy"
  description    = "Permite a A1.Flex (instance principal) gerenciar objetos so no bucket oikos-backups"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.backup.name} to manage objects in compartment id ${var.compartment_ocid} where target.bucket.name = 'oikos-backups'"
  ]
}

# O proprio servico de Object Storage (nao a VM) precisa de permissao explicita
# pra executar as acoes de delete automaticas do lifecycle policy acima -
# sem essa policy o apply falha com "InsufficientServicePermissions".
resource "oci_identity_policy" "objectstorage_lifecycle" {
  compartment_id = var.compartment_ocid
  name           = "oikos-objectstorage-lifecycle-policy"
  description    = "Permite o servico Object Storage executar as regras de object lifecycle (expiracao) no bucket oikos-backups"
  statements = [
    "Allow service objectstorage-sa-vinhedo-1 to manage object-family in compartment id ${var.compartment_ocid} where target.bucket.name = 'oikos-backups'"
  ]
}
