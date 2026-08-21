output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_id" {
  description = "Resource ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.main.id
}

output "kube_config_raw" {
  description = "Raw kubeconfig for the AKS cluster. Sensitive — use with care."
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "host" {
  description = "Kubernetes API server host (private FQDN)."
  value       = azurerm_kubernetes_cluster.main.kube_config[0].host
  sensitive   = true
}

output "kubelet_identity_object_id" {
  description = "Object ID of the AKS kubelet user-assigned managed identity."
  value       = azurerm_user_assigned_identity.aks_kubelet.principal_id
}

output "kubelet_identity_client_id" {
  description = "Client ID of the AKS kubelet user-assigned managed identity."
  value       = azurerm_user_assigned_identity.aks_kubelet.client_id
}

output "control_plane_identity_principal_id" {
  description = "Principal ID of the AKS control-plane user-assigned managed identity."
  value       = azurerm_user_assigned_identity.aks_control_plane.principal_id
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity federation."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "node_resource_group" {
  description = "Name of the auto-generated node resource group."
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace used for AKS monitoring."
  value       = azurerm_log_analytics_workspace.aks.id
}
