provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      Project     = "aws-dbks-infra"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
