output "bucket_names" {
  description = "Nomes dos buckets S3 criados"
  value = {
    for key, bucket in aws_s3_bucket.buckets : key => bucket.bucket
  }
}

output "bucket_arns" {
  description = "ARNs dos buckets S3 criados"
  value = {
    for key, bucket in aws_s3_bucket.buckets : key => bucket.arn
  }
}

output "bucket_ids" {
  description = "IDs dos buckets S3 criados"
  value = {
    for key, bucket in aws_s3_bucket.buckets : key => bucket.id
  }
}

