terraform {
  backend "s3" {
    bucket       = "dbks-infra-s3-tf-state"
    key          = "envs/prod/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
