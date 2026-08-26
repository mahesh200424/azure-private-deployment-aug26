output "vm_name" { value = azurerm_linux_virtual_machine.agent.name }
output "private_ip_address" { value = azurerm_network_interface.agent.private_ip_address }
output "principal_id" {
  description = "System-assigned managed identity principal ID for least-privilege Azure role assignments."
  value       = azurerm_linux_virtual_machine.agent.identity[0].principal_id
}
