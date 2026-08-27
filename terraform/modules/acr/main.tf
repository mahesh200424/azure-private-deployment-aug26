locals {
  name_prefix = "${var.environment}-private"

  common_tags = {
    environment = var.environment
    managed_by  = "terraform"
    module      = "acr"
  }
}

resource "azurerm_container_registry" "main" {
  name                          = var.acr_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false

  zone_redundancy_enabled = false

  identity {
    type = "SystemAssigned"
  }

  retention_policy {
    days    = 7
    enabled = true
  }

  network_rule_set {
    default_action = "Deny"
  }

  tags = local.common_tags
}

resource "azurerm_role_assignment" "agent_acr_push" {
  count                = var.push_principal_id == null ? 0 : 1
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = var.push_principal_id
}

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
