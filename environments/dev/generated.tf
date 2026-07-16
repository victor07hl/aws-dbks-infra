# __generated__ by Terraform
# Please review these resources and move them into your main configuration files.

# __generated__ by Terraform from "arn:aws:iam::252231277941:policy/dbks-dev-policy-s3-file-events"
resource "aws_iam_policy" "file_events" {
  description = "The IAM policy grants Databricks permission to update your buckets event notification configuration, create an SNS topic, create an SQS queue, and subscribe the SQS queue to the SNS topic"
  name        = "dbks-dev-policy-s3-file-events"
  name_prefix = null
  path        = "/"
  policy = jsonencode({
    Statement = [{
      Action   = ["s3:GetBucketNotification", "s3:PutBucketNotification", "sns:ListSubscriptionsByTopic", "sns:GetTopicAttributes", "sns:SetTopicAttributes", "sns:CreateTopic", "sns:TagResource", "sns:Publish", "sns:Subscribe", "sqs:CreateQueue", "sqs:DeleteMessage", "sqs:ReceiveMessage", "sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes", "sqs:SetQueueAttributes", "sqs:TagQueue", "sqs:ChangeMessageVisibility", "sqs:PurgeQueue"]
      Effect   = "Allow"
      Resource = ["arn:aws:s3:::<BUCKET>", "arn:aws:sqs:*:*:*", "arn:aws:sns:*:*:*"]
      Sid      = "ManagedFileEventsSetupStatement"
      }, {
      Action   = ["sqs:ListQueues", "sqs:ListQueueTags", "sns:ListTopics"]
      Effect   = "Allow"
      Resource = "*"
      Sid      = "ManagedFileEventsListStatement"
      }, {
      Action   = ["sns:Unsubscribe", "sns:DeleteTopic", "sqs:DeleteQueue"]
      Effect   = "Allow"
      Resource = ["arn:aws:sqs:*:*:*", "arn:aws:sns:*:*:*"]
      Sid      = "ManagedFileEventsTeardownStatement"
    }]
    Version = "2012-10-17"
  })
  tags     = {}
  tags_all = {}
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

# __generated__ by Terraform from "dbks-dev-trust-role-ws"
resource "aws_iam_role" "storage" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "c20bd1a1-9022-4ee1-9b47-c91f3ddd7245"
        }
      }
      Effect = "Allow"
      Principal = {
        AWS = ["arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL", "arn:aws:iam::252231277941:role/dbks-dev-trust-role-ws"]
      }
    }]
    Version = "2012-10-17"
  })
  description           = "this is the role the databricks user take to perform actions on s3"
  force_detach_policies = false
  max_session_duration  = 3600
  name                  = "dbks-dev-trust-role-ws"
  name_prefix           = null
  path                  = "/"
  permissions_boundary  = null
  tags                  = {}
  tags_all              = {}
}

# __generated__ by Terraform from "arn:aws:iam::252231277941:policy/dbks-dev-bucket-policy"
resource "aws_iam_policy" "bucket" {
  description = "This IAM policy grants read and write access"
  name        = "dbks-dev-bucket-policy"
  name_prefix = null
  path        = "/"
  policy = jsonencode({
    Statement = [{
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Effect   = "Allow"
      Resource = "arn:aws:s3:::dbks-infra-dev-s3-ws/unity-catalog/*"
      }, {
      Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
      Effect   = "Allow"
      Resource = "arn:aws:s3:::dbks-infra-dev-s3-ws"
      }, {
      Action   = ["sts:AssumeRole"]
      Effect   = "Allow"
      Resource = ["arn:aws:iam::252231277941:role/dbks-dev-trust-role-ws"]
    }]
    Version = "2012-10-17"
  })
  tags     = {}
  tags_all = {}
}

# __generated__ by Terraform from "dbks-dev-trust-role-ws/arn:aws:iam::252231277941:policy/dbks-dev-policy-s3-file-events"
resource "aws_iam_role_policy_attachment" "storage_file_events" {
  policy_arn = "arn:aws:iam::252231277941:policy/dbks-dev-policy-s3-file-events"
  role       = "dbks-dev-trust-role-ws"
}

# __generated__ by Terraform from "dbks-dev-trust-role-ws/arn:aws:iam::252231277941:policy/dbks-dev-bucket-policy"
resource "aws_iam_role_policy_attachment" "storage_bucket" {
  policy_arn = "arn:aws:iam::252231277941:policy/dbks-dev-bucket-policy"
  role       = "dbks-dev-trust-role-ws"
}

