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

# Instance Principal - ver docs/infrastructure.md (Storage)
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

resource "oci_identity_policy" "objectstorage_lifecycle" {
  compartment_id = var.compartment_ocid
  name           = "oikos-objectstorage-lifecycle-policy"
  description    = "Permite o servico Object Storage executar as regras de object lifecycle (expiracao) no bucket oikos-backups"
  statements = [
    "Allow service objectstorage-sa-vinhedo-1 to manage object-family in compartment id ${var.compartment_ocid} where target.bucket.name = 'oikos-backups'"
  ]
}

resource "time_sleep" "wait_for_objectstorage_policy" {
  depends_on      = [oci_identity_policy.objectstorage_lifecycle]
  create_duration = "30s"
}

# Retencao nativa OCI de 7 dias - ver docs/infrastructure.md (Storage, ticket 08)
resource "oci_objectstorage_object_lifecycle_policy" "backups" {
  depends_on = [time_sleep.wait_for_objectstorage_policy]

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
