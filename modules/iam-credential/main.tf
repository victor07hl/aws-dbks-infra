# __generated__ by Terraform from "dbks-infra-dev-ws-role"
resource "aws_iam_role" "credential" {
  name        = var.role_name
  description = var.role_description
  path        = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::414351767826:root"
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

# __generated__ by Terraform from "dbks-infra-dev-ws-role:dbks-dev-ws-policy"
resource "aws_iam_role_policy" "credential" {
  name = var.policy_name
  role = aws_iam_role.credential.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Stmt1403287045000"
        Effect   = "Allow"
        Action   = ["ec2:AssociateIamInstanceProfile", "ec2:AttachVolume", "ec2:AuthorizeSecurityGroupEgress", "ec2:AuthorizeSecurityGroupIngress", "ec2:CancelSpotInstanceRequests", "ec2:CreateTags", "ec2:CreateVolume", "ec2:DeleteTags", "ec2:DeleteVolume", "ec2:DescribeAvailabilityZones", "ec2:DescribeIamInstanceProfileAssociations", "ec2:DescribeInstanceStatus", "ec2:DescribeInstances", "ec2:DescribeInternetGateways", "ec2:DescribeNatGateways", "ec2:DescribeNetworkAcls", "ec2:DescribePrefixLists", "ec2:DescribeReservedInstancesOfferings", "ec2:DescribeRouteTables", "ec2:DescribeSecurityGroups", "ec2:DescribeSpotInstanceRequests", "ec2:DescribeSpotPriceHistory", "ec2:DescribeSubnets", "ec2:DescribeVolumes", "ec2:DescribeVpcAttribute", "ec2:DescribeVpcs", "ec2:DetachVolume", "ec2:DisassociateIamInstanceProfile", "ec2:ReplaceIamInstanceProfileAssociation", "ec2:RequestSpotInstances", "ec2:RevokeSecurityGroupEgress", "ec2:RevokeSecurityGroupIngress", "ec2:RunInstances", "ec2:TerminateInstances", "ec2:DescribeFleetHistory", "ec2:ModifyFleet", "ec2:DeleteFleets", "ec2:DescribeFleetInstances", "ec2:DescribeFleets", "ec2:CreateFleet", "ec2:DeleteLaunchTemplate", "ec2:GetLaunchTemplateData", "ec2:CreateLaunchTemplate", "ec2:DescribeLaunchTemplates", "ec2:DescribeLaunchTemplateVersions", "ec2:ModifyLaunchTemplate", "ec2:DeleteLaunchTemplateVersions", "ec2:CreateLaunchTemplateVersion", "ec2:AssignPrivateIpAddresses", "ec2:GetSpotPlacementScores"]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = ["iam:CreateServiceLinkedRole", "iam:PutRolePolicy"]
        Condition = {
          StringLike = {
            "iam:AWSServiceName" = "spot.amazonaws.com"
          }
        }
        Resource = "arn:aws:iam::*:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
      }
    ]
  })
}
