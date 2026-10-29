variable "region" {
  description = "AWS region for the bootstrap buckets"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the Terraform role (owner/name)"
  type        = string
  default     = "arunkumarm-tech/multi-cloud-banking-devsecops"
}

variable "deploy_environments" {
  description = "Protected GitHub environments allowed to assume the apply role"
  type        = list(string)
  default     = ["dev", "prod", "dr-exception", "lab-janitor"]
}

variable "allowed_instance_types" {
  description = "Cost guard: EC2 instance types the apply role may launch"
  type        = list(string)
  default     = ["t3.medium", "t3.large", "t3a.medium", "t3a.large"]
}
