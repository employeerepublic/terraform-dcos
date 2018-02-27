# this persists the terraform state to the S3 bucket
# meaning terraform can be run from anywhere without copying .tfstate files
terraform {
  backend "s3" {
    bucket  = "yapster-terraform-dcos-20180227"
    key     = "yapster-20180227.tfstate"
    region  = "eu-west-1"
    profile = "terraform-dcos"
  }
}