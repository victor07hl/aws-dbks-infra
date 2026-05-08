terraform {
  backend "s3" {
    bucket       = "<TF_STATE_BUCKET>"
    key          = "<STATE_KEY>"
    region       = "<REGION>"
    encrypt      = true
    use_lockfile = true
  }
}
