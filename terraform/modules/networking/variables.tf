variable "location" {
  description = "Azure region for all networking resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Resource Group to create."
  type        = string
}

variable "environment" {
  description = "Deployment environment name used in resource naming."
  type        = string
}

variable "vnet_address_space" {
  description = "Address space CIDR for the Virtual Network."
  type        = string
}

variable "aks_subnet_cidr" {
  description = "CIDR block for the AKS nodes subnet."
  type        = string
}

variable "pe_subnet_cidr" {
  description = "CIDR block for the Private Endpoints subnet."
  type        = string
}

variable "agent_subnet_cidr" {
  description = "CIDR block for the private Azure DevOps agent subnet."
  type        = string
}
