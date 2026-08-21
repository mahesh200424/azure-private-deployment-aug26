# ─────────────────────────────────────────────────────────────
# Module: keyvault
# Creates: Key Vault (fully private, RBAC), Private Endpoint,
#          Private DNS Zone, VNet link,
#          Role Assignment for AKS kubelet identity
# ─────────────────────────────────────────────────────────────

data "azurerm_client_config" "current" {}

locals {
  name_prefix = "${var.environment}-private"

  common_tags = {
    environment = var.environment
    managed_by  = "terraform"
    module      = "keyvault"
  }
}

# ─────────────────────────────────────────────────────────────
# Key Vault
# ─────────────────────────────────────────────────────────────
resource "azurerm_key_vault" "main" {
  name                          = var.keyvault_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "premium"
  soft_delete_retention_days    = 90
  purge_protection_enabled      = true
  public_network_access_enabled = false

  # Use Azure RBAC for access control (no legacy access policies)
  enable_rbac_authorization = true

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules       = []
    virtual_network_subnet_ids = []
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────
# Private DNS Zone — privatelink.vaultcore.azure.net
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  name                  = "link-kv-${local.name_prefix}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  tags                  = local.common_tags
}

# ─────────────────────────────────────────────────────────────
# Private Endpoint for Key Vault
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_endpoint" "keyvault" {
  name                = "pe-kv-${local.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-kv-${local.name_prefix}"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kv-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.keyvault.id]
  }
}

# ─────────────────────────────────────────────────────────────
# RBAC — Grant AKS kubelet identity 'Key Vault Secrets User'
# This allows the Secrets Store CSI driver to read secrets.
# ─────────────────────────────────────────────────────────────
resource "azurerm_role_assignment" "aks_kubelet_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.aks_kubelet_identity_id

  # Avoid duplicate role assignment errors on re-apply
  skip_service_principal_aad_check = true
}

# ─────────────────────────────────────────────────────────────
# RBAC — Grant the Terraform caller 'Key Vault Administrator'
# so it can manage secrets during bootstrapping.
# Remove or restrict this in day-2 operations.
# ─────────────────────────────────────────────────────────────
resource "azurerm_role_assignment" "terraform_kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}
