# __generated__ by Terraform from "dbks-dev-trust-role-ws"
resource "aws_iam_role" "storage" {
  name        = var.role_name
  description = var.role_description
  path        = "/"

  # Self-assuming trust policy: lists both the UCMasterRole and this role's
  # own ARN, per the Unity Catalog storage-credential two-pass apply pattern
  # (see docs/folder-structure.md - modules/iam-storage).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = [
          "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL",
          "arn:aws:iam::252231277941:role/${var.role_name}",
        ]
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = var.databricks_account_id
        }
      }
    }]
  })

  force_detach_policies = false
  max_session_duration  = 3600
}

# __generated__ by Terraform from "arn:aws:iam::252231277941:policy/dbks-dev-bucket-policy"
resource "aws_iam_policy" "bucket" {
  name        = var.bucket_policy_name
  description = "This IAM policy grants read and write access"
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${var.bucket_arn}/unity-catalog/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = var.bucket_arn
      },
      {
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = [aws_iam_role.storage.arn]
      }
    ]
  })
}

# __generated__ by Terraform from "arn:aws:iam::252231277941:policy/dbks-dev-policy-s3-file-events"
resource "aws_iam_policy" "file_events" {
  name        = var.file_events_policy_name
  description = "The IAM policy grants Databricks permission to update your buckets event notification configuration, create an SNS topic, create an SQS queue, and subscribe the SQS queue to the SNS topic"
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManagedFileEventsSetupStatement"
        Effect = "Allow"
        Action = ["s3:GetBucketNotification", "s3:PutBucketNotification", "sns:ListSubscriptionsByTopic", "sns:GetTopicAttributes", "sns:SetTopicAttributes", "sns:CreateTopic", "sns:TagResource", "sns:Publish", "sns:Subscribe", "sqs:CreateQueue", "sqs:DeleteMessage", "sqs:ReceiveMessage", "sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes", "sqs:SetQueueAttributes", "sqs:TagQueue", "sqs:ChangeMessageVisibility", "sqs:PurgeQueue"]
        # "<BUCKET>" is a literal, unresolved placeholder inherited verbatim
        # from the already-applied live policy. Pre-existing defect in the
        # imported resource, out of scope for this state-only move.
        Resource = ["arn:aws:s3:::<BUCKET>", "arn:aws:sqs:*:*:*", "arn:aws:sns:*:*:*"]
      },
      {
        Sid      = "ManagedFileEventsListStatement"
        Effect   = "Allow"
        Action   = ["sqs:ListQueues", "sqs:ListQueueTags", "sns:ListTopics"]
        Resource = "*"
      },
      {
        Sid      = "ManagedFileEventsTeardownStatement"
        Effect   = "Allow"
        Action   = ["sns:Unsubscribe", "sns:DeleteTopic", "sqs:DeleteQueue"]
        Resource = ["arn:aws:sqs:*:*:*", "arn:aws:sns:*:*:*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "storage_bucket" {
  role       = aws_iam_role.storage.name
  policy_arn = aws_iam_policy.bucket.arn
}

resource "aws_iam_role_policy_attachment" "storage_file_events" {
  role       = aws_iam_role.storage.name
  policy_arn = aws_iam_policy.file_events.arn
}

# __generated__ by Terraform from "dbks-infra-dev-s3-ws"
resource "aws_s3_bucket_policy" "workspace" {
  bucket = var.bucket_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Grant Databricks Access"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::414351767826:root"
        }
        Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Condition = {
          StringEquals = {
            "aws:PrincipalTag/DatabricksAccountId" = var.databricks_account_id
          }
        }
        Resource = ["${var.bucket_arn}/*", var.bucket_arn]
      },
      {
        Sid    = "Prevent DBFS from accessing Unity Catalog metastore"
        Effect = "Deny"
        Principal = {
          AWS = "arn:aws:iam::414351767826:root"
        }
        Action   = "s3:*"
        Resource = "${var.bucket_arn}/unity-catalog/*"
      }
    ]
  })
}
