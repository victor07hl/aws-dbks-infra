# __generated__ by Terraform from "dbks-infra-dev-s3-ws"
resource "aws_s3_bucket" "workspace" {
  bucket = var.bucket_name
}

# __generated__ by Terraform from "dbks-infra-dev-s3-ws"
# NOTE: status is "Disabled" in the already-applied dev bucket, which
# contradicts the "versioning ON" security baseline in CLAUDE.md. Preserved
# verbatim — this is a pure state-move, not a config fix.
resource "aws_s3_bucket_versioning" "workspace" {
  bucket = aws_s3_bucket.workspace.id

  versioning_configuration {
    status = "Disabled"
  }
}

# __generated__ by Terraform from "dbks-infra-dev-s3-ws"
# NOTE: SSE is AES256 (not KMS) in the already-applied dev bucket, which
# contradicts the "SSE-KMS per-env CMK" security baseline in CLAUDE.md.
# Preserved verbatim — this is a pure state-move, not a config fix.
resource "aws_s3_bucket_server_side_encryption_configuration" "workspace" {
  bucket = aws_s3_bucket.workspace.id

  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# __generated__ by Terraform from "dbks-infra-dev-s3-ws"
resource "aws_s3_bucket_public_access_block" "workspace" {
  bucket                  = aws_s3_bucket.workspace.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
