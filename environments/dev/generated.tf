# __generated__ by Terraform
# Please review these resources and move them into your main configuration files.

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
