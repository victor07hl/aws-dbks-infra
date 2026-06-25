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

# __generated__ by Terraform from "dbks-infra-dev-ws-role:dbks-dev-ws-policy"
resource "aws_iam_role_policy" "credential" {
  name        = "dbks-dev-ws-policy"
  name_prefix = null
  policy = jsonencode({
    Statement = [{
      Action   = ["ec2:AssociateIamInstanceProfile", "ec2:AttachVolume", "ec2:AuthorizeSecurityGroupEgress", "ec2:AuthorizeSecurityGroupIngress", "ec2:CancelSpotInstanceRequests", "ec2:CreateTags", "ec2:CreateVolume", "ec2:DeleteTags", "ec2:DeleteVolume", "ec2:DescribeAvailabilityZones", "ec2:DescribeIamInstanceProfileAssociations", "ec2:DescribeInstanceStatus", "ec2:DescribeInstances", "ec2:DescribeInternetGateways", "ec2:DescribeNatGateways", "ec2:DescribeNetworkAcls", "ec2:DescribePrefixLists", "ec2:DescribeReservedInstancesOfferings", "ec2:DescribeRouteTables", "ec2:DescribeSecurityGroups", "ec2:DescribeSpotInstanceRequests", "ec2:DescribeSpotPriceHistory", "ec2:DescribeSubnets", "ec2:DescribeVolumes", "ec2:DescribeVpcAttribute", "ec2:DescribeVpcs", "ec2:DetachVolume", "ec2:DisassociateIamInstanceProfile", "ec2:ReplaceIamInstanceProfileAssociation", "ec2:RequestSpotInstances", "ec2:RevokeSecurityGroupEgress", "ec2:RevokeSecurityGroupIngress", "ec2:RunInstances", "ec2:TerminateInstances", "ec2:DescribeFleetHistory", "ec2:ModifyFleet", "ec2:DeleteFleets", "ec2:DescribeFleetInstances", "ec2:DescribeFleets", "ec2:CreateFleet", "ec2:DeleteLaunchTemplate", "ec2:GetLaunchTemplateData", "ec2:CreateLaunchTemplate", "ec2:DescribeLaunchTemplates", "ec2:DescribeLaunchTemplateVersions", "ec2:ModifyLaunchTemplate", "ec2:DeleteLaunchTemplateVersions", "ec2:CreateLaunchTemplateVersion", "ec2:AssignPrivateIpAddresses", "ec2:GetSpotPlacementScores"]
      Effect   = "Allow"
      Resource = ["*"]
      Sid      = "Stmt1403287045000"
      }, {
      Action = ["iam:CreateServiceLinkedRole", "iam:PutRolePolicy"]
      Condition = {
        StringLike = {
          "iam:AWSServiceName" = "spot.amazonaws.com"
        }
      }
      Effect   = "Allow"
      Resource = "arn:aws:iam::*:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
    }]
    Version = "2012-10-17"
  })
  role = "dbks-infra-dev-ws-role"
}

# __generated__ by Terraform
resource "aws_route_table" "private" {
  propagating_vgws = []
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = "nat-01c22cd9e5d35b605"
  }
  tags = {
    Name = "dbks-infra-dev-private-rt"
  }
  tags_all = {
    Name = "dbks-infra-dev-private-rt"
  }
  vpc_id = "vpc-0c0888b82c6975777"
}

# __generated__ by Terraform
resource "aws_route_table" "public" {
  propagating_vgws = []
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "igw-04fd7b10931650f25"
  }
  tags = {
    Name = "dbks-infra-dev-public-rt"
  }
  tags_all = {
    Name = "dbks-infra-dev-public-rt"
  }
  vpc_id = "vpc-0c0888b82c6975777"
}

# __generated__ by Terraform
resource "aws_subnet" "public" {
  assign_ipv6_address_on_creation                = false
  availability_zone                              = "us-east-2a"
  cidr_block                                     = "10.0.0.0/24"
  customer_owned_ipv4_pool                       = null
  enable_dns64                                   = false
  enable_resource_name_dns_a_record_on_launch    = false
  enable_resource_name_dns_aaaa_record_on_launch = false
  ipv6_cidr_block                                = null
  ipv6_native                                    = false
  map_public_ip_on_launch                        = false
  outpost_arn                                    = null
  private_dns_hostname_type_on_launch            = "ip-name"
  tags = {
    Name = "dbks-infra-dev-public-subnet"
  }
  tags_all = {
    Name = "dbks-infra-dev-public-subnet"
  }
  vpc_id = "vpc-0c0888b82c6975777"
}

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

# __generated__ by Terraform from "subnet-09f846f4d0b575d53/rtb-0f6274c0f3b5db937"
resource "aws_route_table_association" "public" {
  gateway_id     = null
  route_table_id = "rtb-0f6274c0f3b5db937"
  subnet_id      = "subnet-09f846f4d0b575d53"
}

# __generated__ by Terraform from "dbks-infra-dev-s3-ws"
resource "aws_s3_bucket_public_access_block" "workspace" {
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = "dbks-infra-dev-s3-ws"
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# __generated__ by Terraform from "sg-0929e3fd034aebd7f"
resource "aws_security_group" "workspace" {
  description = "launch-wizard-3 created 2026-04-28T20:04:33.678Z"
  egress = [{
    cidr_blocks      = ["0.0.0.0/0"]
    description      = ""
    from_port        = 0
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "-1"
    security_groups  = []
    self             = false
    to_port          = 0
  }]
  ingress                = []
  name                   = "launch-wizard-3"
  name_prefix            = null
  revoke_rules_on_delete = null
  tags                   = {}
  tags_all               = {}
  vpc_id                 = "vpc-0c0888b82c6975777"
}

# __generated__ by Terraform from "subnet-0d425a507a3750f95/rtb-0e11f517003820532"
resource "aws_route_table_association" "private_2" {
  gateway_id     = null
  route_table_id = "rtb-0e11f517003820532"
  subnet_id      = "subnet-0d425a507a3750f95"
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

# __generated__ by Terraform from "dbks-infra-dev-ws-role"
resource "aws_iam_role" "credential" {
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
        AWS = "arn:aws:iam::414351767826:root"
      }
    }]
    Version = "2012-10-17"
  })
  description           = "this is the role used for the dbks dev "
  force_detach_policies = false
  max_session_duration  = 3600
  name                  = "dbks-infra-dev-ws-role"
  name_prefix           = null
  path                  = "/"
  permissions_boundary  = null
  tags                  = {}
  tags_all              = {}
}

# __generated__ by Terraform from "igw-04fd7b10931650f25"
resource "aws_internet_gateway" "this" {
  tags = {
    Name = "dbks-infra-dev-IGW"
  }
  tags_all = {
    Name = "dbks-infra-dev-IGW"
  }
  vpc_id = "vpc-0c0888b82c6975777"
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

# __generated__ by Terraform
resource "aws_nat_gateway" "this" {
  allocation_id            = "eipalloc-0aed97f3f156aa724"
  connectivity_type        = "public"
  private_ip               = "10.0.0.79"
  secondary_allocation_ids = []
  subnet_id                = "subnet-09f846f4d0b575d53"
  tags = {
    Name = "dbks-infra-dev-NATG"
  }
  tags_all = {
    Name = "dbks-infra-dev-NATG"
  }
}

# __generated__ by Terraform from "dbks-dev-trust-role-ws/arn:aws:iam::252231277941:policy/dbks-dev-policy-s3-file-events"
resource "aws_iam_role_policy_attachment" "storage_file_events" {
  policy_arn = "arn:aws:iam::252231277941:policy/dbks-dev-policy-s3-file-events"
  role       = "dbks-dev-trust-role-ws"
}

# __generated__ by Terraform from "eipalloc-0aed97f3f156aa724"
resource "aws_eip" "nat" {
  address                   = null
  associate_with_private_ip = null
  customer_owned_ipv4_pool  = null
  domain                    = "vpc"
  instance                  = null
  ipam_pool_id              = null
  network_border_group      = "us-east-2"
  network_interface         = "eni-0cca9ef7f384554cb"
  public_ipv4_pool          = "amazon"
  tags                      = {}
  tags_all                  = {}
}

# __generated__ by Terraform from "dbks-dev-trust-role-ws/arn:aws:iam::252231277941:policy/dbks-dev-bucket-policy"
resource "aws_iam_role_policy_attachment" "storage_bucket" {
  policy_arn = "arn:aws:iam::252231277941:policy/dbks-dev-bucket-policy"
  role       = "dbks-dev-trust-role-ws"
}

# __generated__ by Terraform
resource "aws_subnet" "private_1" {
  assign_ipv6_address_on_creation                = false
  availability_zone                              = "us-east-2b"
  cidr_block                                     = "10.0.1.0/24"
  customer_owned_ipv4_pool                       = null
  enable_dns64                                   = false
  enable_resource_name_dns_a_record_on_launch    = false
  enable_resource_name_dns_aaaa_record_on_launch = false
  ipv6_cidr_block                                = null
  ipv6_native                                    = false
  map_public_ip_on_launch                        = false
  outpost_arn                                    = null
  private_dns_hostname_type_on_launch            = "ip-name"
  tags = {
    Name = "dbks-infra-dev-private-subnet"
  }
  tags_all = {
    Name = "dbks-infra-dev-private-subnet"
  }
  vpc_id = "vpc-0c0888b82c6975777"
}

# __generated__ by Terraform
resource "aws_subnet" "private_2" {
  assign_ipv6_address_on_creation                = false
  availability_zone                              = "us-east-2a"
  cidr_block                                     = "10.0.2.0/24"
  customer_owned_ipv4_pool                       = null
  enable_dns64                                   = false
  enable_resource_name_dns_a_record_on_launch    = false
  enable_resource_name_dns_aaaa_record_on_launch = false
  ipv6_cidr_block                                = null
  ipv6_native                                    = false
  map_public_ip_on_launch                        = false
  outpost_arn                                    = null
  private_dns_hostname_type_on_launch            = "ip-name"
  tags = {
    Name = "dbks-infra-dev-private-subnet-2"
  }
  tags_all = {
    Name = "dbks-infra-dev-private-subnet-2"
  }
  vpc_id = "vpc-0c0888b82c6975777"
}

# __generated__ by Terraform from "subnet-04526bd022d251edf/rtb-0e11f517003820532"
resource "aws_route_table_association" "private_1" {
  gateway_id     = null
  route_table_id = "rtb-0e11f517003820532"
  subnet_id      = "subnet-04526bd022d251edf"
}

# __generated__ by Terraform
resource "aws_vpc" "this" {
  assign_generated_ipv6_cidr_block     = false
  cidr_block                           = "10.0.0.0/16"
  enable_dns_hostnames                 = true
  enable_dns_support                   = true
  enable_network_address_usage_metrics = false
  instance_tenancy                     = "default"
  ipv4_ipam_pool_id                    = null
  ipv4_netmask_length                  = null
  ipv6_cidr_block                      = null
  ipv6_cidr_block_network_border_group = null
  ipv6_ipam_pool_id                    = null
  tags = {
    Name = "dbks-infra"
  }
  tags_all = {
    Name = "dbks-infra"
  }
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
