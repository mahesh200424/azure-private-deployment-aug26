resource "azurerm_user_assigned_identity" "myapp" {
  name                = "mi-myapp-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = {
    environment = var.environment
    managed_by  = "terraform"
    purpose     = "myapp-key-vault-access"
  }
}

resource "azurerm_federated_identity_credential" "myapp" {
  name                = "fic-myapp-${var.environment}"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.myapp.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:myapp:myapp"
}
