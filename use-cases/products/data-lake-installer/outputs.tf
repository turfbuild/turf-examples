output "raw_bucket" {
  value = aws_s3_bucket.raw.bucket
}

output "curated_bucket" {
  value = aws_s3_bucket.curated.bucket
}

output "catalog_database" {
  value = aws_glue_catalog_database.lake.name
}

output "athena_workgroup" {
  value = aws_athena_workgroup.lake.name
}

output "vpc_id" {
  value = aws_vpc.lake.id
}
