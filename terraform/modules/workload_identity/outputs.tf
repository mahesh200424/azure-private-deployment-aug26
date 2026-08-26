output "client_id" {
  description = "Client ID to set on the myapp Kubernetes ServiceAccount."
  value       = azurerm_user_assigned_identity.myapp.client_id
}

output "principal_id" {
  description = "Principal ID granted Key Vault Secrets User."
  value       = azurerm_user_assigned_identity.myapp.principal_id
}
