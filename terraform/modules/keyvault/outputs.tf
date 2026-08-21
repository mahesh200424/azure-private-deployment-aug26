output "keyvault_id" {
  description = "Resource ID of the Azure Key Vault."
  value       = azurerm_key_vault.main.id
}

output "keyvault_name" {
  description = "Name of the Azure Key Vault."
  value       = azurerm_key_vault.main.name
}

output "keyvault_uri" {
  description = "URI of the Azure Key Vault."
  value       = azurerm_key_vault.main.vault_uri
}

output "private_endpoint_ip" {
  description = "Private IP address of the Key Vault private endpoint."
  value       = azurerm_private_endpoint.keyvault.private_service_connection[0].private_ip_address
}
