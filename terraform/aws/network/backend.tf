terraform {
  backend "s3" {
    key          = "aws/network/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
