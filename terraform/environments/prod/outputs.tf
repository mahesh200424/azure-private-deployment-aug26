output "aks_cluster_name" {
  description = "Name of the provisioned AKS cluster."
  value       = module.aks.cluster_name
}

output "acr_login_server" {
  description = "Login server URL of the Azure Container Registry."
  value       = module.acr.login_server
}

output "keyvault_uri" {
  description = "URI of the Azure Key Vault."
  value       = module.keyvault.keyvault_uri
}

output "vnet_id" {
  description = "Resource ID of the Virtual Network."
  value       = module.networking.vnet_id
}

output "workload_identity_client_id" {
  description = "Set this value on the myapp ServiceAccount annotation."
  value       = module.workload_identity.client_id
}

output "agent_vm_name" {
  description = "Private VM that must be registered in Azure DevOps private-vnet-pool."
  value       = module.azure_devops_agent.vm_name
}
