variable "environment" {
  description = "Environment name (dev or prod), used to derive the resource name prefix"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod."
  }
}

variable "region" {
  description = "AWS region the network resources are deployed into"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones used by the subnets, e.g. [\"us-east-2a\", \"us-east-2b\"]"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnet(s)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets, one per AZ"
  type        = list(string)
}

variable "nat_gateway_count" {
  description = "Number of NAT gateways to create. Only 1 is supported today since the module has a single public subnet; one-per-AZ for prod is a follow-up"
  type        = number
  default     = 1

  validation {
    condition     = var.nat_gateway_count == 1
    error_message = "Only a single NAT gateway is supported until the module has one public subnet per AZ."
  }
}

variable "security_group_name" {
  description = "Name of the workspace security group, inherited from the manually-provisioned launch-wizard default"
  type        = string
  default     = "launch-wizard-3"
}
