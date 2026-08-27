variable "location" {
  description = "Azure region for AKS resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Resource Group where AKS will be created."
  type        = string
}

variable "environment" {
  description = "Deployment environment name used in resource naming."
  type        = string
}

variable "vnet_id" {
  description = "Resource ID of the VNet. Required for the control plane to link the private DNS zone."
  type        = string
}

variable "aks_subnet_id" {
  description = "Resource ID of the subnet for AKS nodes (Azure CNI)."
  type        = string
}

variable "acr_id" {
  description = "Resource ID of the Azure Container Registry. Kubelet identity gets AcrPull."
  type        = string
}

variable "node_count" {
  description = "Initial node count for both system and user node pools."
  type        = number
  default     = 3
}

variable "vm_size" {
  description = "VM SKU for AKS node pools."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "dns_prefix" {
  description = "DNS prefix for the private AKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster. Leave null to use the latest stable."
  type        = string
  default     = null
}
