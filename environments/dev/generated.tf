# __generated__ by Terraform
# Please review these resources and move them into your main configuration files.

# __generated__ by Terraform from "dbks-infra-dev-s3-ws"
resource "aws_s3_bucket_server_side_encryption_configuration" "workspace" {
  bucket                = "dbks-infra-dev-s3-ws"
  expected_bucket_owner = null
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      kms_master_key_id = null
      sse_algorithm     = "AES256"
    }
  }
}

# __generated__ by Terraform from "dbks-infra-dev-s3-ws"
resource "aws_s3_bucket_policy" "workspace" {
  bucket = "dbks-infra-dev-s3-ws"
  policy = jsonencode({
    Statement = [{
      Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
      Condition = {
        StringEquals = {
          "aws:PrincipalTag/DatabricksAccountId" = "c20bd1a1-9022-4ee1-9b47-c91f3ddd7245"
        }
      }
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::414351767826:root"
      }
      Resource = ["arn:aws:s3:::dbks-infra-dev-s3-ws/*", "arn:aws:s3:::dbks-infra-dev-s3-ws"]
      Sid      = "Grant Databricks Access"
      }, {
      Action = "s3:*"
      Effect = "Deny"
      Principal = {
        AWS = "arn:aws:iam::414351767826:root"
      }
      Resource = "arn:aws:s3:::dbks-infra-dev-s3-ws/unity-catalog/*"
      Sid      = "Prevent DBFS from accessing Unity Catalog metastore"
    }]
    Version = "2012-10-17"
  })
}

# __generated__ by Terraform from "dbks-infra-dev-s3-ws"
resource "aws_s3_bucket_public_access_block" "workspace" {
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = "dbks-infra-dev-s3-ws"
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# __generated__ by Terraform from "dbks-infra-dev-s3-ws"
resource "aws_s3_bucket" "workspace" {
  bucket              = "dbks-infra-dev-s3-ws"
  bucket_prefix       = null
  force_destroy       = null
  object_lock_enabled = false
  tags                = {}
  tags_all            = {}
}

# __generated__ by Terraform from "dbks-infra-dev-s3-ws"
resource "aws_s3_bucket_versioning" "workspace" {
  bucket                = "dbks-infra-dev-s3-ws"
  expected_bucket_owner = null
  mfa                   = null
  versioning_configuration {
    mfa_delete = null
    status     = "Disabled"
  }
}
