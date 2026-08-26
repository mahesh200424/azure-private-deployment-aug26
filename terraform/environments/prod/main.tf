terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }

}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

provider "azuread" {}

# ─────────────────────────────────────────────────────────────
# Networking
# ─────────────────────────────────────────────────────────────
module "networking" {
  source = "../../modules/networking"

  location            = var.location
  resource_group_name = var.resource_group_name
  environment         = var.environment
  vnet_address_space  = var.vnet_address_space
  aks_subnet_cidr     = var.aks_subnet_cidr
  pe_subnet_cidr      = var.pe_subnet_cidr
  agent_subnet_cidr   = var.agent_subnet_cidr
}

# ─────────────────────────────────────────────────────────────
# Azure Container Registry
# ─────────────────────────────────────────────────────────────
module "acr" {
  source = "../../modules/acr"

  location            = var.location
  resource_group_name = module.networking.resource_group_name
  environment         = var.environment
  acr_name            = var.acr_name
  pe_subnet_id        = module.networking.pe_subnet_id
  vnet_id             = module.networking.vnet_id
  push_principal_id   = module.azure_devops_agent.principal_id

  depends_on = [module.networking, module.azure_devops_agent]
}

# ─────────────────────────────────────────────────────────────
# Dedicated workload identity
# ─────────────────────────────────────────────────────────────
module "workload_identity" {
  source = "../../modules/workload_identity"

  location            = var.location
  resource_group_name = module.networking.resource_group_name
  environment         = var.environment
  oidc_issuer_url     = module.aks.oidc_issuer_url

  depends_on = [module.aks]
}

# ─────────────────────────────────────────────────────────────
# AKS
# ─────────────────────────────────────────────────────────────
module "aks" {
  source = "../../modules/aks"

  location            = var.location
  resource_group_name = module.networking.resource_group_name
  environment         = var.environment
  aks_subnet_id       = module.networking.aks_subnet_id
  acr_id              = module.acr.acr_id
  node_count          = var.aks_node_count
  vm_size             = var.aks_vm_size
  dns_prefix          = "${var.environment}-aks"

  depends_on = [module.networking, module.acr]
}

# ─────────────────────────────────────────────────────────────
# Key Vault
# ─────────────────────────────────────────────────────────────
module "keyvault" {
  source = "../../modules/keyvault"

  location                       = var.location
  resource_group_name            = module.networking.resource_group_name
  environment                    = var.environment
  keyvault_name                  = var.keyvault_name
  pe_subnet_id                   = module.networking.pe_subnet_id
  vnet_id                        = module.networking.vnet_id
  workload_identity_principal_id = module.workload_identity.principal_id

  depends_on = [module.networking, module.workload_identity]
}

# ─────────────────────────────────────────────────────────────
# Private Azure DevOps agent host
# ─────────────────────────────────────────────────────────────
module "azure_devops_agent" {
  source = "../../modules/azure_devops_agent"

  location             = var.location
  resource_group_name  = module.networking.resource_group_name
  environment          = var.environment
  subnet_id            = module.networking.agent_subnet_id
  admin_username       = var.agent_admin_username
  admin_ssh_public_key = var.agent_admin_ssh_public_key
  vm_size              = var.agent_vm_size

  depends_on = [module.networking]
}
