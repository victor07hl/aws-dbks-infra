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
