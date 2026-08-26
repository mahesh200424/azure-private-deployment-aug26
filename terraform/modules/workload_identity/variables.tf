variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "environment" { type = string }
variable "oidc_issuer_url" {
  description = "OIDC issuer URL exposed by the AKS cluster."
  type        = string
}
