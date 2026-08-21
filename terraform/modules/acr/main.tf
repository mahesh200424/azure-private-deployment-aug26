# ─────────────────────────────────────────────────────────────
# Module: acr
# Creates: Premium ACR (fully private), Private Endpoint,
#          Private DNS Zone, VNet link
# ─────────────────────────────────────────────────────────────

locals {
  name_prefix = "${var.environment}-private"

  common_tags = {
    environment = var.environment
    managed_by  = "terraform"
    module      = "acr"
  }
}

# ─────────────────────────────────────────────────────────────
# Azure Container Registry
# ─────────────────────────────────────────────────────────────
resource "azurerm_container_registry" "main" {
  name                          = var.acr_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false

  # Zone redundancy requires Premium SKU
  zone_redundancy_enabled = true

  # System-assigned managed identity for ACR tasks / geo-replication
  identity {
    type = "SystemAssigned"
  }

  # Enforce content trust for image signing
  trust_policy {
    enabled = true
  }

  # Retain untagged manifests for 7 days before quarantine
  retention_policy {
    days    = 7
    enabled = true
  }

  network_rule_set {
    default_action = "Deny"
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────
# Private DNS Zone — privatelink.azurecr.io
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "link-acr-${local.name_prefix}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  tags                  = local.common_tags
}

# ─────────────────────────────────────────────────────────────
# Private Endpoint for ACR
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_endpoint" "acr" {
  name                = "pe-acr-${local.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-acr-${local.name_prefix}"
    private_connection_resource_id = azurerm_container_registry.main.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "acr-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr.id]
  }
}
