variable "location" {
  description = "Azure region where all resources will be deployed."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group."
  type        = string
}

variable "environment" {
  description = "Deployment environment name (e.g. prod, staging)."
  type        = string
  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment must be one of: prod, staging, dev."
  }
}

variable "aks_node_count" {
  description = "Initial number of nodes in the AKS system node pool."
  type        = number
  default     = 3
  validation {
    condition     = var.aks_node_count >= 1 && var.aks_node_count <= 100
    error_message = "aks_node_count must be between 1 and 100."
  }
}

variable "aks_vm_size" {
  description = "VM SKU for AKS node pools."
  type        = string
  default     = "Standard_D4s_v7"
}

variable "acr_name" {
  description = "Globally unique name for the Azure Container Registry (alphanumeric, 5-50 chars)."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.acr_name))
    error_message = "acr_name must be 5-50 alphanumeric characters."
  }
}

variable "keyvault_name" {
  description = "Globally unique name for the Azure Key Vault (3-24 alphanumeric and hyphens)."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,24}$", var.keyvault_name))
    error_message = "keyvault_name must be 3-24 alphanumeric characters or hyphens."
  }
}

variable "vnet_address_space" {
  description = "CIDR block for the Virtual Network."
  type        = string
  default     = "10.0.0.0/8"
}

variable "aks_subnet_cidr" {
  description = "CIDR block for the AKS nodes subnet."
  type        = string
  default     = "10.1.0.0/16"
}

variable "pe_subnet_cidr" {
  description = "CIDR block for the Private Endpoints subnet."
  type        = string
  default     = "10.2.0.0/24"
}

variable "agent_subnet_cidr" {
  description = "CIDR block for the private Azure DevOps agent subnet."
  type        = string
  default     = "10.3.0.0/24"
}

variable "agent_admin_username" {
  description = "Linux administrator name for the private Azure DevOps agent VM."
  type        = string
  default     = "azureuser"
}

variable "agent_admin_ssh_public_key" {
  description = "SSH public key for break-glass administration of the private agent VM."
  type        = string
}

variable "agent_vm_size" {
  description = "Temporary private Azure DevOps agent VM size."
  type        = string
  default     = "Standard_B2s"
}

variable "deploy_azure_devops_agent" {
  description = "Whether to deploy the private Azure DevOps agent VM. Disable when regional vCPU quota is reserved for AKS."
  type        = bool
  default     = true
}
