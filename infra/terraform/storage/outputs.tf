output "bucket_name" {
  description = "Nome do bucket de backup"
  value       = oci_objectstorage_bucket.backups.name
}

output "namespace" {
  description = "Namespace do Object Storage (necessario pros scripts de backup montarem a URL do bucket)"
  value       = data.oci_objectstorage_namespace.this.namespace
}
