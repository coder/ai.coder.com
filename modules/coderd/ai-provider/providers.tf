terraform {
  required_providers {
    coderd = {
      source = "coder/coderd"
    }
    aws = {
      source = "hashicorp/aws"
    }
    time = {
      source = "hashicorp/time"
    }
  }
  backend "s3" {}
}