resource "aws_s3_bucket" "buckets" {
  for_each = var.s3_buckets

  bucket        = each.value.name
  force_destroy = each.value.force_destroy

  tags = merge(
    var.common_tags,
    {
      Component   = "Storage"
      BucketName  = each.key
    }
  )
}

resource "aws_s3_bucket_versioning" "buckets" {
  for_each = var.s3_buckets

  bucket = aws_s3_bucket.buckets[each.key].id

  versioning_configuration {
    status = each.value.versioning
  }
}

resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each = var.s3_buckets

  bucket = aws_s3_bucket.buckets[each.key].id

  block_public_acls       = each.value.block_public
  block_public_policy     = each.value.block_public
  ignore_public_acls      = each.value.block_public
  restrict_public_buckets = each.value.block_public
}

