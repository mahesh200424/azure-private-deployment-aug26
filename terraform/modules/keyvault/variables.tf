variable "location" {
  description = "Azure region for Key Vault resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Resource Group where the Key Vault will be created."
  type        = string
}

variable "environment" {
  description = "Deployment environment name used in resource naming."
  type        = string
}

variable "keyvault_name" {
  description = "Globally unique name for the Azure Key Vault (3-24 alphanumeric and hyphens)."
  type        = string
}

variable "pe_subnet_id" {
  description = "Resource ID of the subnet where the Key Vault private endpoint will be placed."
  type        = string
}

variable "vnet_id" {
  description = "Resource ID of the Virtual Network to link the private DNS zone to."
  type        = string
}

variable "aks_kubelet_identity_id" {
  description = "Object ID of the AKS kubelet managed identity. Granted 'Key Vault Secrets User'."
  type        = string
}
