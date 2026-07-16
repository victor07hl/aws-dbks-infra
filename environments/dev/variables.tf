variable "environment" {
  description = "Environment name, used in default_tags and resource naming"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region the network resources are deployed into"
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones used by the subnets, e.g. [\"us-east-2a\", \"us-east-2b\"]"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnet(s)"
  type        = list(string)
  default     = ["10.0.0.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets, one per AZ"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "databricks_account_id" {
  description = "Databricks account ID, used as the sts:ExternalId condition on cross-account trust policies"
  type        = string
  default     = "c20bd1a1-9022-4ee1-9b47-c91f3ddd7245"
}

variable "credential_role_name" {
  description = "Name of the Databricks cross-account credential IAM role"
  type        = string
  default     = "dbks-infra-dev-ws-role"
}
