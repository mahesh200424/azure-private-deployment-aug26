output "acr_id" {
  description = "Resource ID of the Azure Container Registry."
  value       = azurerm_container_registry.main.id
}

output "login_server" {
  description = "Login server URL of the Azure Container Registry."
  value       = azurerm_container_registry.main.login_server
}

output "acr_name" {
  description = "Name of the Azure Container Registry."
  value       = azurerm_container_registry.main.name
}

output "principal_id" {
  description = "Principal ID of the system-assigned managed identity of the ACR."
  value       = azurerm_container_registry.main.identity[0].principal_id
}

output "private_endpoint_ip" {
  description = "Private IP address of the ACR private endpoint."
  value       = azurerm_private_endpoint.acr.private_service_connection[0].private_ip_address
}
