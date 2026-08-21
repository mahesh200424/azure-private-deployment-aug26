output "resource_group_name" {
  description = "Name of the created Resource Group."
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "Resource ID of the Resource Group."
  value       = azurerm_resource_group.main.id
}

output "vnet_id" {
  description = "Resource ID of the Virtual Network."
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the Virtual Network."
  value       = azurerm_virtual_network.main.name
}

output "aks_subnet_id" {
  description = "Resource ID of the AKS nodes subnet."
  value       = azurerm_subnet.aks.id
}

output "pe_subnet_id" {
  description = "Resource ID of the Private Endpoints subnet."
  value       = azurerm_subnet.pe.id
}

output "nat_gateway_id" {
  description = "Resource ID of the NAT Gateway."
  value       = azurerm_nat_gateway.main.id
}

output "nat_public_ip" {
  description = "Public IP address of the NAT Gateway."
  value       = azurerm_public_ip.nat.ip_address
}
