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

  backend "azurerm" {}
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

  depends_on = [module.networking]
}

# ─────────────────────────────────────────────────────────────
# Key Vault
# ─────────────────────────────────────────────────────────────
module "keyvault" {
  source = "../../modules/keyvault"

  location                 = var.location
  resource_group_name      = module.networking.resource_group_name
  environment              = var.environment
  keyvault_name            = var.keyvault_name
  pe_subnet_id             = module.networking.pe_subnet_id
  vnet_id                  = module.networking.vnet_id
  aks_kubelet_identity_id  = module.aks.kubelet_identity_object_id

  depends_on = [module.networking, module.aks]
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
