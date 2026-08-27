variable "location" {
  description = "Azure region for ACR resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Resource Group where ACR will be created."
  type        = string
}

variable "environment" {
  description = "Deployment environment name used in resource naming."
  type        = string
}

variable "acr_name" {
  description = "Globally unique name for the Azure Container Registry."
  type        = string
}

variable "pe_subnet_id" {
  description = "Resource ID of the subnet where the ACR private endpoint will be placed."
  type        = string
}

variable "vnet_id" {
  description = "Resource ID of the Virtual Network to link the private DNS zone to."
  type        = string
}

variable "push_principal_id" {
  description = "Optional principal ID granted AcrPush on this registry."
  type        = string
  default     = null
  nullable    = true
}
